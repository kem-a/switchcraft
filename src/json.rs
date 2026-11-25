// json-glib through FFI. The Vala version read and wrote all JSON with it,
// so parsing rules, member order, escaping, pretty printing and error
// messages stay the same.

use gtk::glib;
use gtk::glib::ffi as gffi;
use gtk::glib::gobject_ffi;
use gtk::glib::translate::{FromGlibPtrFull, IntoGlib};
use std::ffi::{CStr, c_char, c_int, c_uint};
use std::marker::PhantomData;

use crate::util::cstr;

#[repr(C)]
struct RawNode {
    _private: [u8; 0],
}
#[repr(C)]
struct RawObject {
    _private: [u8; 0],
}
#[repr(C)]
struct RawArray {
    _private: [u8; 0],
}

const NODE_OBJECT: c_int = 0;

unsafe extern "C" {
    fn json_parser_new() -> *mut gobject_ffi::GObject;
    fn json_parser_load_from_data(
        parser: *mut gobject_ffi::GObject,
        data: *const c_char,
        length: isize,
        error: *mut *mut gffi::GError,
    ) -> gffi::gboolean;
    fn json_parser_get_root(parser: *mut gobject_ffi::GObject) -> *mut RawNode;

    fn json_node_new(node_type: c_int) -> *mut RawNode;
    fn json_node_take_object(node: *mut RawNode, object: *mut RawObject);
    fn json_node_unref(node: *mut RawNode);
    fn json_node_get_node_type(node: *mut RawNode) -> c_int;
    fn json_node_get_value_type(node: *mut RawNode) -> glib::ffi::GType;
    fn json_node_get_string(node: *mut RawNode) -> *const c_char;
    fn json_node_get_boolean(node: *mut RawNode) -> gffi::gboolean;
    fn json_node_get_int(node: *mut RawNode) -> i64;
    fn json_node_get_object(node: *mut RawNode) -> *mut RawObject;
    fn json_node_get_array(node: *mut RawNode) -> *mut RawArray;

    fn json_object_new() -> *mut RawObject;
    fn json_object_unref(object: *mut RawObject);
    fn json_object_has_member(object: *mut RawObject, name: *const c_char) -> gffi::gboolean;
    fn json_object_get_member(object: *mut RawObject, name: *const c_char) -> *mut RawNode;
    fn json_object_get_members(object: *mut RawObject) -> *mut gffi::GList;
    fn json_object_set_string_member(
        object: *mut RawObject,
        name: *const c_char,
        value: *const c_char,
    );
    fn json_object_set_boolean_member(
        object: *mut RawObject,
        name: *const c_char,
        value: gffi::gboolean,
    );
    fn json_object_set_int_member(object: *mut RawObject, name: *const c_char, value: i64);
    fn json_object_set_array_member(
        object: *mut RawObject,
        name: *const c_char,
        value: *mut RawArray,
    );

    fn json_array_new() -> *mut RawArray;
    fn json_array_unref(array: *mut RawArray);
    fn json_array_get_length(array: *mut RawArray) -> c_uint;
    fn json_array_get_element(array: *mut RawArray, index: c_uint) -> *mut RawNode;
    fn json_array_add_object_element(array: *mut RawArray, value: *mut RawObject);

    fn json_generator_new() -> *mut gobject_ffi::GObject;
    fn json_generator_set_root(generator: *mut gobject_ffi::GObject, node: *mut RawNode);
    fn json_generator_set_pretty(generator: *mut gobject_ffi::GObject, pretty: gffi::gboolean);
    fn json_generator_set_indent(generator: *mut gobject_ffi::GObject, indent: c_uint);
    fn json_generator_to_data(
        generator: *mut gobject_ffi::GObject,
        length: *mut usize,
    ) -> *mut c_char;
}

#[derive(PartialEq, Eq, Clone, Copy, Debug)]
pub enum NodeType {
    Object,
    Array,
    Value,
    Null,
}

// A parsed document. Nodes borrow from it.
pub struct Parser(*mut gobject_ffi::GObject);

impl Parser {
    // Parser.load_from_data () with the data as a C string, so it ends at
    // the first NUL like the Vala strings did
    pub fn load(data: &[u8]) -> Result<Parser, glib::Error> {
        let length = data.iter().position(|b| *b == 0).unwrap_or(data.len());
        unsafe {
            let parser = Parser(json_parser_new());
            let mut error = std::ptr::null_mut();
            if json_parser_load_from_data(
                parser.0,
                data.as_ptr().cast(),
                length as isize,
                &mut error,
            ) == 0
            {
                return Err(glib::Error::from_glib_full(error));
            }
            Ok(parser)
        }
    }

    pub fn root(&self) -> Option<Node<'_>> {
        unsafe { Node::wrap(json_parser_get_root(self.0)) }
    }
}

impl Drop for Parser {
    fn drop(&mut self) {
        unsafe { gobject_ffi::g_object_unref(self.0) }
    }
}

#[derive(Clone, Copy)]
pub struct Node<'a>(*mut RawNode, PhantomData<&'a Parser>);

impl<'a> Node<'a> {
    unsafe fn wrap(ptr: *mut RawNode) -> Option<Node<'a>> {
        (!ptr.is_null()).then_some(Node(ptr, PhantomData))
    }

    pub fn node_type(&self) -> NodeType {
        match unsafe { json_node_get_node_type(self.0) } {
            0 => NodeType::Object,
            1 => NodeType::Array,
            2 => NodeType::Value,
            _ => NodeType::Null,
        }
    }

    fn value_type(&self) -> glib::Type {
        unsafe { glib::translate::from_glib(json_node_get_value_type(self.0)) }
    }

    pub fn is_string(&self) -> bool {
        self.value_type() == glib::Type::STRING
    }

    pub fn is_bool(&self) -> bool {
        self.value_type() == glib::Type::BOOL
    }

    pub fn is_int(&self) -> bool {
        self.value_type() == glib::Type::I64
    }

    // string_value () in the Vala version: the string, or None for any
    // other type
    pub fn string_value(&self) -> Option<String> {
        if !self.is_string() {
            return None;
        }
        unsafe {
            let ptr = json_node_get_string(self.0);
            (!ptr.is_null()).then(|| CStr::from_ptr(ptr).to_string_lossy().into_owned())
        }
    }

    pub fn boolean(&self) -> bool {
        unsafe { json_node_get_boolean(self.0) != 0 }
    }

    pub fn int(&self) -> i64 {
        unsafe { json_node_get_int(self.0) }
    }

    pub fn object(&self) -> Object<'a> {
        Object(unsafe { json_node_get_object(self.0) }, PhantomData)
    }

    pub fn array(&self) -> Array<'a> {
        Array(unsafe { json_node_get_array(self.0) }, PhantomData)
    }
}

#[derive(Clone, Copy)]
pub struct Object<'a>(*mut RawObject, PhantomData<&'a Parser>);

impl<'a> Object<'a> {
    pub fn has_member(&self, name: &str) -> bool {
        let n = cstr(name);
        unsafe { json_object_has_member(self.0, n.as_ptr()) != 0 }
    }

    pub fn member(&self, name: &str) -> Option<Node<'a>> {
        let n = cstr(name);
        unsafe { Node::wrap(json_object_get_member(self.0, n.as_ptr())) }
    }

    // Member names in insertion order, as foreach_member visits them
    pub fn members(&self) -> Vec<String> {
        let mut names = Vec::new();
        unsafe {
            let list = json_object_get_members(self.0);
            let mut item = list;
            while !item.is_null() {
                names.push(
                    CStr::from_ptr((*item).data.cast())
                        .to_string_lossy()
                        .into_owned(),
                );
                item = (*item).next;
            }
            gffi::g_list_free(list);
        }
        names
    }
}

#[derive(Clone, Copy)]
pub struct Array<'a>(*mut RawArray, PhantomData<&'a Parser>);

impl<'a> Array<'a> {
    pub fn elements(&self) -> Vec<Node<'a>> {
        unsafe {
            (0..json_array_get_length(self.0))
                .filter_map(|i| Node::wrap(json_array_get_element(self.0, i)))
                .collect()
        }
    }
}

// An object being built for output
pub struct ObjectBuilder(*mut RawObject);

impl ObjectBuilder {
    pub fn new() -> Self {
        ObjectBuilder(unsafe { json_object_new() })
    }

    pub fn set_string(&self, name: &str, value: &str) {
        let (n, v) = (cstr(name), cstr(value));
        unsafe { json_object_set_string_member(self.0, n.as_ptr(), v.as_ptr()) }
    }

    pub fn set_bool(&self, name: &str, value: bool) {
        let n = cstr(name);
        unsafe { json_object_set_boolean_member(self.0, n.as_ptr(), value.into_glib()) }
    }

    pub fn set_int(&self, name: &str, value: i64) {
        let n = cstr(name);
        unsafe { json_object_set_int_member(self.0, n.as_ptr(), value) }
    }

    pub fn set_array(&self, name: &str, array: ArrayBuilder) {
        let n = cstr(name);
        unsafe { json_object_set_array_member(self.0, n.as_ptr(), array.into_raw()) }
    }

    fn into_raw(self) -> *mut RawObject {
        let ptr = self.0;
        std::mem::forget(self);
        ptr
    }

    // Generator with pretty = true and indent = 2
    pub fn into_pretty_data(self) -> String {
        unsafe {
            let node = json_node_new(NODE_OBJECT);
            json_node_take_object(node, self.into_raw());
            let generator = json_generator_new();
            json_generator_set_root(generator, node);
            json_generator_set_pretty(generator, 1);
            json_generator_set_indent(generator, 2);
            let data = json_generator_to_data(generator, std::ptr::null_mut());
            let text = CStr::from_ptr(data).to_string_lossy().into_owned();
            gffi::g_free(data.cast());
            gobject_ffi::g_object_unref(generator);
            json_node_unref(node);
            text
        }
    }
}

impl Drop for ObjectBuilder {
    fn drop(&mut self) {
        unsafe { json_object_unref(self.0) }
    }
}

pub struct ArrayBuilder(*mut RawArray);

impl ArrayBuilder {
    pub fn new() -> Self {
        ArrayBuilder(unsafe { json_array_new() })
    }

    pub fn add_object(&self, object: ObjectBuilder) {
        unsafe { json_array_add_object_element(self.0, object.into_raw()) }
    }

    fn into_raw(self) -> *mut RawArray {
        let ptr = self.0;
        std::mem::forget(self);
        ptr
    }
}

impl Drop for ArrayBuilder {
    fn drop(&mut self) {
        unsafe { json_array_unref(self.0) }
    }
}
