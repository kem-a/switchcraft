// Constants management window

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gio, glib, pango};
use std::cell::{OnceCell, RefCell};

use crate::i18n::gettext;
use crate::store;
use crate::util::{self, StrTable};

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct ConstantsWindow {
        pub constants: RefCell<Option<StrTable>>,
        pub listbox: OnceCell<gtk::ListBox>,
        pub content_stack: OnceCell<gtk::Stack>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for ConstantsWindow {
        const NAME: &'static str = "SwitchcraftConstantsWindow";
        type Type = super::ConstantsWindow;
        type ParentType = adw::Window;
    }

    impl ObjectImpl for ConstantsWindow {}
    impl WidgetImpl for ConstantsWindow {}
    impl WindowImpl for ConstantsWindow {}
    impl AdwWindowImpl for ConstantsWindow {}
}

glib::wrapper! {
    pub struct ConstantsWindow(ObjectSubclass<imp::ConstantsWindow>)
        @extends adw::Window, gtk::Window, gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget, gtk::Native, gtk::Root,
                    gtk::ShortcutManager;
}

impl ConstantsWindow {
    pub fn new(parent: &gtk::Window) -> Self {
        let obj: Self = glib::Object::new();
        *obj.imp().constants.borrow_mut() = Some(StrTable::new());

        obj.set_title(Some(&gettext("Constants")));
        obj.set_default_size(600, 450);
        obj.set_transient_for(Some(parent));
        obj.set_modal(true);

        obj.build_ui();
        obj.load_constants();
        obj
    }

    fn build_ui(&self) {
        let imp = self.imp();
        let toolbar_view = adw::ToolbarView::new();

        let header_bar = adw::HeaderBar::new();
        toolbar_view.add_top_bar(&header_bar);

        let add_button = gtk::Button::new();
        add_button.set_icon_name("list-add-symbolic");
        add_button.set_tooltip_text(Some(&gettext("Add Constant")));
        add_button.add_css_class("flat");
        add_button.connect_clicked(glib::clone!(
            #[weak(rename_to = window)]
            self,
            move |_| window.show_constant_dialog("", "")
        ));
        header_bar.pack_start(&add_button);

        // Main content area
        let content_box = gtk::Box::new(gtk::Orientation::Vertical, 12);
        content_box.set_margin_top(24);
        content_box.set_margin_bottom(24);
        content_box.set_margin_start(24);
        content_box.set_margin_end(24);

        let description = gtk::Label::new(Some(&gettext(
            // xgettext:no-rust-format
            "Define constants to use in your commands. Reference them with $NAME or ${NAME}.",
        )));
        description.set_xalign(0.0);
        description.set_wrap(true);
        description.add_css_class("body");
        content_box.append(&description);

        let listbox = gtk::ListBox::new();
        listbox.set_selection_mode(gtk::SelectionMode::None);
        listbox.add_css_class("boxed-list");
        imp.listbox.set(listbox.clone()).unwrap();

        let scrolled = gtk::ScrolledWindow::new();
        scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
        scrolled.set_hexpand(true);
        scrolled.set_vexpand(true);
        scrolled.set_child(Some(&listbox));

        let placeholder = adw::StatusPage::new();
        placeholder.set_icon_name(Some("text-x-generic-symbolic"));
        placeholder.set_title(&gettext("No Constants"));
        placeholder.set_description(Some(&gettext("Click the '+' button to define a constant.")));

        let content_stack = gtk::Stack::new();
        content_stack.set_transition_type(gtk::StackTransitionType::Crossfade);
        content_stack.set_hexpand(true);
        content_stack.set_vexpand(true);
        content_stack.add_named(&scrolled, Some("list"));
        content_stack.add_named(&placeholder, Some("placeholder"));
        imp.content_stack.set(content_stack.clone()).unwrap();

        content_box.append(&content_stack);

        toolbar_view.set_content(Some(&content_box));
        self.set_content(Some(&toolbar_view));
    }

    fn with_constants<R>(&self, f: impl FnOnce(&StrTable) -> R) -> R {
        f(self.imp().constants.borrow().as_ref().unwrap())
    }

    fn load_constants(&self) {
        let constants = StrTable::new();
        let mut needs_save = false;
        for (key, value) in store::get_constants().entries() {
            let normalized = normalize_constant_value(&value);
            constants.insert(&key, &normalized);
            if normalized != value {
                needs_save = true;
            }
        }
        *self.imp().constants.borrow_mut() = Some(constants);

        if needs_save {
            self.save_constants();
        }

        self.refresh_list();
    }

    fn refresh_list(&self) {
        let imp = self.imp();
        let listbox = imp.listbox.get().unwrap();
        // Clear existing rows
        while let Some(row) = listbox.row_at_index(0) {
            listbox.remove(&row);
        }

        // Add rows for each constant (sorted by name)
        let (keys, size) = self.with_constants(|c| (c.sorted_keys(), c.size()));
        for name in keys {
            if let Some(value) = self.with_constants(|c| c.lookup(&name)) {
                listbox.append(&self.create_constant_row(&name, &value));
            }
        }

        // Show appropriate view
        imp.content_stack
            .get()
            .unwrap()
            .set_visible_child_name(if size > 0 { "list" } else { "placeholder" });
    }

    fn create_constant_row(&self, name: &str, value: &str) -> adw::ActionRow {
        let row = adw::ActionRow::new();
        // Values often contain & < > which are not valid markup
        row.set_use_markup(false);
        row.set_title(name);
        row.set_subtitle(value);
        row.set_activatable(false);

        let controls_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        controls_box.set_valign(gtk::Align::Center);

        let name = name.to_string();
        let edit_button = gtk::Button::from_icon_name("document-edit-symbolic");
        edit_button.add_css_class("flat");
        edit_button.set_tooltip_text(Some(&gettext("Edit constant")));
        edit_button.connect_clicked(glib::clone!(
            #[weak(rename_to = window)]
            self,
            #[strong]
            name,
            move |_| window.on_edit_constant(&name)
        ));
        controls_box.append(&edit_button);

        let remove_button = gtk::Button::from_icon_name("user-trash-symbolic");
        remove_button.add_css_class("flat");
        remove_button.set_tooltip_text(Some(&gettext("Remove constant")));
        remove_button.connect_clicked(glib::clone!(
            #[weak(rename_to = window)]
            self,
            #[strong]
            name,
            move |_| window.on_remove_constant(&name)
        ));
        controls_box.append(&remove_button);

        row.add_suffix(&controls_box);
        row
    }

    fn on_edit_constant(&self, name: &str) {
        if let Some(value) = self.with_constants(|c| c.lookup(name)) {
            self.show_constant_dialog(name, &value);
        }
    }

    fn on_remove_constant(&self, name: &str) {
        self.with_constants(|c| c.remove(name));
        self.save_constants();
        self.refresh_list();
    }

    fn show_constant_dialog(&self, existing_name: &str, existing_value: &str) {
        let editing = !existing_name.is_empty();
        let title = if editing {
            gettext("Edit Constant")
        } else {
            gettext("Add Constant")
        };

        let dialog = adw::AlertDialog::new(
            Some(&title),
            Some(&gettext("Define a constant name and value.")),
        );
        dialog.add_response("cancel", &gettext("Cancel"));
        dialog.add_response(
            "save",
            &if editing {
                gettext("Save")
            } else {
                gettext("Add")
            },
        );
        dialog.set_default_response(Some("save"));
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);

        // Create form
        let form_box = gtk::Box::new(gtk::Orientation::Vertical, 12);
        form_box.set_margin_top(12);
        form_box.set_margin_bottom(12);
        form_box.set_size_request(450, -1);

        let fields = gtk::ListBox::new();
        fields.set_selection_mode(gtk::SelectionMode::None);
        fields.add_css_class("boxed-list");
        form_box.append(&fields);

        let name_entry = adw::EntryRow::new();
        name_entry.set_title(&gettext("Constant name (e.g., D2DL_SCHEMA)"));
        if !existing_name.is_empty() {
            name_entry.set_text(existing_name);
            // Don't allow renaming
            name_entry.set_sensitive(false);
        }
        fields.append(&name_entry);

        let value_entry = adw::EntryRow::new();
        value_entry.set_title(&gettext(
            "Value (e.g., org.gnome.shell.extensions.dash2dock-lite)",
        ));
        if !existing_value.is_empty() {
            value_entry.set_text(existing_value);
        }
        fields.append(&value_entry);

        let hint_label = gtk::Label::new(Some(&gettext(
            // xgettext:no-rust-format
            "Use in commands as $NAME or ${NAME}. Names use letters, numbers and underscores.",
        )));
        hint_label.set_xalign(0.0);
        hint_label.set_wrap(true);
        hint_label.set_wrap_mode(pango::WrapMode::WordChar);
        hint_label.set_max_width_chars(50);
        hint_label.add_css_class("dim-label");
        hint_label.add_css_class("caption");
        form_box.append(&hint_label);

        // Save stays disabled until the input can be saved, so nothing typed
        // is dropped
        let update = glib::clone!(
            #[weak]
            dialog,
            #[weak]
            name_entry,
            #[weak]
            value_entry,
            move || update_save_response(&dialog, &name_entry, &value_entry)
        );
        name_entry.connect_changed(glib::clone!(
            #[strong]
            update,
            move |_| update()
        ));
        value_entry.connect_changed(glib::clone!(
            #[strong]
            update,
            move |_| update()
        ));
        update();

        dialog.set_extra_child(Some(&form_box));
        let existing_name = existing_name.to_string();
        dialog.clone().choose(
            Some(self),
            gio::Cancellable::NONE,
            glib::clone!(
                #[weak(rename_to = window)]
                self,
                move |response_id| {
                    window.on_constant_dialog_response(
                        &response_id,
                        &existing_name,
                        &name_entry,
                        &value_entry,
                    );
                }
            ),
        );
    }

    fn on_constant_dialog_response(
        &self,
        response_id: &str,
        old_name: &str,
        name_entry: &adw::EntryRow,
        value_entry: &adw::EntryRow,
    ) {
        if response_id != "save" {
            return;
        }

        let name = util::strip(&name_entry.text()).to_string();
        let normalized_value = normalize_constant_value(&value_entry.text());

        self.with_constants(|c| {
            // If editing, remove old name if it changed
            if !old_name.is_empty() && old_name != name {
                c.remove(old_name);
            }

            c.insert(&name, &normalized_value);
        });
        self.save_constants();
        self.refresh_list();
    }

    fn save_constants(&self) {
        self.with_constants(store::save_constants);
    }
}

fn update_save_response(
    dialog: &adw::AlertDialog,
    name_entry: &adw::EntryRow,
    value_entry: &adw::EntryRow,
) {
    let text = name_entry.text();
    let name = util::strip(&text);
    let name_valid = is_valid_variable_name(name);
    if !name.is_empty() && !name_valid {
        name_entry.add_css_class("error");
    } else {
        name_entry.remove_css_class("error");
    }
    dialog.set_response_enabled(
        "save",
        name_valid && !normalize_constant_value(&value_entry.text()).is_empty(),
    );
}

pub(crate) fn normalize_constant_value(value: &str) -> String {
    let trimmed = util::strip(value);
    let bytes = trimmed.as_bytes();
    if bytes.len() >= 2 {
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        if (first == b'\'' && last == b'\'') || (first == b'"' && last == b'"') {
            return trimmed[1..trimmed.len() - 1].to_string();
        }
    }
    trimmed.to_string()
}

fn is_valid_variable_name(name: &str) -> bool {
    let Some(first) = name.chars().next() else {
        return false;
    };

    // First character must be letter or underscore
    if !util::unichar_isalpha(first) && first != '_' {
        return false;
    }

    // Remaining characters must be alphanumeric or underscore
    name.chars().all(|c| util::unichar_isalnum(c) || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_values() {
        assert_eq!(normalize_constant_value("  'a b'  "), "a b");
        assert_eq!(normalize_constant_value("\"x\""), "x");
        assert_eq!(normalize_constant_value("'x\""), "'x\"");
        assert_eq!(normalize_constant_value("'"), "'");
    }

    #[test]
    fn checks_names() {
        assert!(is_valid_variable_name("_A1"));
        assert!(is_valid_variable_name("Äb"));
        assert!(!is_valid_variable_name("1A"));
        assert!(!is_valid_variable_name("A-B"));
        assert!(!is_valid_variable_name(""));
    }
}
