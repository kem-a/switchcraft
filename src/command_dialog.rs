// Add or edit a custom command or a built-in setting

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gio, glib, pango};
use std::cell::{OnceCell, RefCell};

use crate::builtins;
use crate::i18n::gettext;
use crate::runner;
use crate::store::{CommandEntry, Commands, THEME_SETTING_IDS};
use crate::util;
use crate::widgets::SlidingToggleGroup;

type SavedCallback = Box<dyn Fn(&str, &str, &str, &str)>;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct CommandDialog {
        pub commands: RefCell<Commands>,
        pub entry: RefCell<Option<CommandEntry>>,
        pub conflict_label: OnceCell<gtk::Label>,
        pub duplicate_label: OnceCell<gtk::Label>,
        pub type_row: OnceCell<adw::ComboRow>,
        pub command_row: OnceCell<gtk::ListBoxRow>,
        pub command_buffer: OnceCell<gtk::TextBuffer>,
        pub error_box: OnceCell<gtk::Box>,
        pub error_label: OnceCell<gtk::Label>,
        pub test_status: OnceCell<gtk::Label>,
        pub test_spinner: OnceCell<adw::Spinner>,
        pub test_button: OnceCell<gtk::Button>,
        pub test_cancellable: RefCell<Option<gio::Cancellable>>,
        pub value_row: OnceCell<adw::ComboRow>,
        pub image_row: OnceCell<adw::ActionRow>,
        pub image_label: OnceCell<gtk::Label>,
        pub mode_group: OnceCell<adw::ToggleGroup>,
        pub value_ids: RefCell<Vec<String>>,
        pub wallpaper_path: RefCell<String>,
        // Built-in settings offered in the Type list, after Custom Command
        pub setting_ids: RefCell<Vec<String>>,
        pub initial_builtin: RefCell<String>,
        pub initial_value: RefCell<String>,
        // builtin and value are empty for a custom command
        pub saved: RefCell<Option<SavedCallback>>,
        pub deleted: RefCell<Option<Box<dyn Fn()>>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for CommandDialog {
        const NAME: &'static str = "SwitchcraftCommandDialog";
        type Type = super::CommandDialog;
        type ParentType = adw::AlertDialog;
    }

    impl ObjectImpl for CommandDialog {}
    impl WidgetImpl for CommandDialog {}
    impl AdwDialogImpl for CommandDialog {}
    impl AdwAlertDialogImpl for CommandDialog {}
}

glib::wrapper! {
    pub struct CommandDialog(ObjectSubclass<imp::CommandDialog>)
        @extends adw::AlertDialog, adw::Dialog, gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget, gtk::ShortcutManager;
}

impl CommandDialog {
    pub fn new(commands: Commands, entry: Option<CommandEntry>, theme: &str) -> Self {
        let heading = if entry.is_some() {
            gettext("Edit Command")
        } else {
            gettext("Add Command")
        };
        let obj: Self = glib::Object::builder().property("heading", heading).build();
        let imp = obj.imp();
        *imp.commands.borrow_mut() = commands;
        *imp.entry.borrow_mut() = entry.clone();

        if entry.is_some() {
            obj.add_response("delete", &gettext("Delete"));
            obj.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
        }
        obj.add_response("cancel", &gettext("Cancel"));
        obj.add_response(
            "save",
            &if entry.is_some() {
                gettext("Save")
            } else {
                gettext("Add")
            },
        );
        obj.set_default_response(Some("save"));
        obj.set_close_response("cancel");
        obj.set_response_appearance("save", adw::ResponseAppearance::Suggested);

        let fields = gtk::ListBox::new();
        fields.set_selection_mode(gtk::SelectionMode::None);
        fields.add_css_class("boxed-list");
        fields.set_size_request(520, -1);

        // First item is a custom command, the rest are the built-in settings
        // for this desktop
        let type_model = gtk::StringList::new(&[]);
        type_model.append(&gettext("Custom Command"));
        let editing = |setting_id: &str| entry.as_ref().is_some_and(|e| e.builtin() == setting_id);
        let mut setting_ids = Vec::new();
        // Wallpaper is always the last entry in the list
        for image in [false, true] {
            for setting_id in THEME_SETTING_IDS {
                if builtins::is_image_setting(setting_id) != image {
                    continue;
                }
                // One from another desktop stays while it is being edited
                if builtins::is_setting_available(setting_id) || editing(setting_id) {
                    setting_ids.push(setting_id.to_string());
                    type_model.append(&builtins::get_builtin_title(setting_id));
                }
            }
        }
        *imp.setting_ids.borrow_mut() = setting_ids;
        let type_row = adw::ComboRow::new();
        type_row.set_title(&gettext("Type"));
        type_row.set_model(Some(&type_model));
        fields.append(&type_row);
        imp.type_row.set(type_row.clone()).unwrap();

        // Multiline, wrapping command field that grows with its text
        let command_title = gtk::Label::new(Some(&gettext("Command")));
        command_title.set_xalign(0.0);
        command_title.add_css_class("caption");
        command_title.add_css_class("dim-label");

        let command_view = gtk::TextView::new();
        command_view.set_wrap_mode(gtk::WrapMode::WordChar);
        command_view.set_accepts_tab(false);
        command_view.add_css_class("command-view");
        let command_buffer = command_view.buffer();
        imp.command_buffer.set(command_buffer.clone()).unwrap();

        let command_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
        command_box.set_margin_top(8);
        command_box.set_margin_bottom(10);
        command_box.set_margin_start(12);
        command_box.set_margin_end(12);
        command_box.append(&command_title);
        command_box.append(&command_view);

        // Output of a failed test, selectable and copyable
        let error_label = gtk::Label::new(None);
        error_label.set_xalign(0.0);
        error_label.set_wrap(true);
        error_label.set_wrap_mode(pango::WrapMode::WordChar);
        error_label.set_max_width_chars(40);
        error_label.set_selectable(true);
        error_label.set_hexpand(true);
        error_label.set_valign(gtk::Align::Start);
        error_label.set_margin_top(8);
        error_label.set_margin_bottom(8);
        error_label.set_margin_start(10);
        error_label.add_css_class("monospace");
        imp.error_label.set(error_label.clone()).unwrap();

        let error_scroll = gtk::ScrolledWindow::new();
        error_scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
        error_scroll.set_propagate_natural_height(true);
        error_scroll.set_max_content_height(160);
        error_scroll.set_child(Some(&error_label));

        let copy_button = gtk::Button::from_icon_name("edit-copy-symbolic");
        copy_button.set_tooltip_text(Some(&gettext("Copy Error")));
        copy_button.set_valign(gtk::Align::Start);
        copy_button.set_margin_top(4);
        copy_button.set_margin_end(4);
        copy_button.add_css_class("flat");
        copy_button.connect_clicked(glib::clone!(
            #[weak]
            obj,
            #[weak]
            error_label,
            move |_| obj.clipboard().set_text(&error_label.text())
        ));

        let error_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        error_box.set_margin_top(6);
        error_box.add_css_class("card");
        error_box.append(&error_scroll);
        error_box.append(&copy_button);
        error_box.set_visible(false);
        command_box.append(&error_box);
        imp.error_box.set(error_box).unwrap();

        let test_status = gtk::Label::new(None);
        test_status.set_xalign(0.0);
        test_status.set_hexpand(true);
        test_status.set_wrap(true);
        imp.test_status.set(test_status.clone()).unwrap();

        let test_spinner = adw::Spinner::new();
        test_spinner.set_visible(false);
        imp.test_spinner.set(test_spinner.clone()).unwrap();

        let test_button = gtk::Button::with_label(&gettext("Test"));
        test_button.connect_clicked(glib::clone!(
            #[weak]
            obj,
            move |_| obj.on_test_command()
        ));
        imp.test_button.set(test_button.clone()).unwrap();

        let test_bar = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        test_bar.set_margin_top(6);
        test_bar.append(&test_status);
        test_bar.append(&test_spinner);
        test_bar.append(&test_button);
        command_box.append(&test_bar);

        let command_row = gtk::ListBoxRow::new();
        command_row.set_activatable(false);
        command_row.set_child(Some(&command_box));
        fields.append(&command_row);
        imp.command_row.set(command_row).unwrap();

        let value_row = adw::ComboRow::new();
        value_row.set_title(&gettext("Value"));
        fields.append(&value_row);
        imp.value_row.set(value_row.clone()).unwrap();

        // Wallpapers are picked as files instead of from a list
        let image_row = adw::ActionRow::new();
        image_row.set_title(&gettext("Image"));
        let image_label = gtk::Label::new(None);
        image_label.set_ellipsize(pango::EllipsizeMode::Middle);
        image_label.set_max_width_chars(20);
        image_row.add_suffix(&image_label);
        imp.image_label.set(image_label).unwrap();
        let browse_button = gtk::Button::with_label(&gettext("Browse…"));
        browse_button.set_valign(gtk::Align::Center);
        browse_button.connect_clicked(glib::clone!(
            #[weak]
            obj,
            move |_| obj.on_browse_wallpaper()
        ));
        image_row.add_suffix(&browse_button);
        image_row.set_activatable_widget(Some(&browse_button));
        fields.append(&image_row);
        imp.image_row.set(image_row).unwrap();

        let mode_toggle = SlidingToggleGroup::for_theme(theme);
        let mode_group = mode_toggle.group();
        imp.mode_group.set(mode_group.clone()).unwrap();
        let mode_row = adw::ActionRow::new();
        mode_row.set_title(&gettext("Mode"));
        mode_row.add_suffix(&mode_toggle);
        fields.append(&mode_row);

        let conflict_label = gtk::Label::new(None);
        conflict_label.set_xalign(0.0);
        conflict_label.set_wrap(true);
        conflict_label.set_max_width_chars(40);
        conflict_label.set_margin_top(12);
        conflict_label.add_css_class("error");
        conflict_label.set_visible(false);
        imp.conflict_label.set(conflict_label.clone()).unwrap();

        let duplicate_label = gtk::Label::new(None);
        duplicate_label.set_xalign(0.0);
        duplicate_label.set_wrap(true);
        duplicate_label.set_max_width_chars(40);
        duplicate_label.set_margin_top(6);
        duplicate_label.add_css_class("warning");
        duplicate_label.set_visible(false);
        imp.duplicate_label.set(duplicate_label.clone()).unwrap();

        let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content.append(&fields);
        content.append(&duplicate_label);
        content.append(&conflict_label);
        obj.set_extra_child(Some(&content));

        // Fill in the entry being edited
        let mut type_index = 0;
        if let Some(entry) = entry.as_ref().filter(|e| !e.builtin().is_empty()) {
            for (i, setting_id) in imp.setting_ids.borrow().iter().enumerate() {
                if *setting_id == entry.builtin() {
                    type_index = i as u32 + 1;
                }
            }
        }
        if type_index > 0 {
            let entry = entry.as_ref().unwrap();
            *imp.initial_builtin.borrow_mut() = entry.builtin();
            *imp.initial_value.borrow_mut() = entry.value();
            if builtins::is_image_setting(&entry.builtin()) {
                obj.set_wallpaper(&entry.value());
            }
        } else if let Some(entry) = &entry {
            command_buffer.set_text(&entry.command());
        }
        type_row.set_selected(type_index);
        obj.on_type_changed();
        obj.update_test_button();

        type_row.connect_selected_notify(glib::clone!(
            #[weak]
            obj,
            move |_| obj.on_type_changed()
        ));
        value_row.connect_selected_notify(glib::clone!(
            #[weak]
            obj,
            move |_| obj.update_save_response()
        ));
        mode_group.connect_active_name_notify(glib::clone!(
            #[weak]
            obj,
            move |_| obj.update_save_response()
        ));
        command_buffer.connect_changed(glib::clone!(
            #[weak]
            obj,
            move |_| obj.update_save_response()
        ));
        command_buffer.connect_changed(glib::clone!(
            #[weak]
            obj,
            move |_| {
                obj.show_test_result(false, None);
                obj.update_test_button();
            }
        ));

        // Stop a test that is still running
        obj.connect_closed(|obj| {
            if let Some(cancellable) = obj.imp().test_cancellable.borrow().as_ref() {
                cancellable.cancel();
            }
        });

        obj.connect_response(None, |obj, response_id| {
            if response_id == "save" {
                obj.emit_saved();
            } else if response_id == "delete"
                && let Some(deleted) = obj.imp().deleted.borrow().as_ref()
            {
                deleted();
            }
        });

        obj
    }

    pub fn connect_saved(&self, f: impl Fn(&str, &str, &str, &str) + 'static) {
        *self.imp().saved.borrow_mut() = Some(Box::new(f));
    }

    pub fn connect_deleted(&self, f: impl Fn() + 'static) {
        *self.imp().deleted.borrow_mut() = Some(Box::new(f));
    }

    fn get_setting_id(&self) -> String {
        let selected = self.imp().type_row.get().unwrap().selected();
        if selected == 0 || selected == gtk::INVALID_LIST_POSITION {
            return String::new();
        }
        self.imp().setting_ids.borrow()[selected as usize - 1].clone()
    }

    fn mode(&self) -> String {
        self.imp()
            .mode_group
            .get()
            .unwrap()
            .active_name()
            .map(|n| n.to_string())
            .unwrap_or_default()
    }

    fn on_type_changed(&self) {
        let imp = self.imp();
        let setting_id = self.get_setting_id();
        imp.command_row
            .get()
            .unwrap()
            .set_visible(setting_id.is_empty());
        imp.image_row
            .get()
            .unwrap()
            .set_visible(builtins::is_image_setting(&setting_id));
        let value_row = imp.value_row.get().unwrap();
        value_row.set_visible(!setting_id.is_empty() && !builtins::is_image_setting(&setting_id));

        if value_row.is_visible() {
            self.fill_values(&setting_id);
        }
        self.update_save_response();
    }

    // Starts at the edited value, or at what the desktop uses now
    fn fill_values(&self, setting_id: &str) {
        let imp = self.imp();
        let mut value_ids = builtins::scan_setting_values(setting_id);
        let model = gtk::StringList::new(&[]);
        for value in &value_ids {
            model.append(&builtins::get_setting_value_label(setting_id, value));
        }

        let current = if setting_id == *imp.initial_builtin.borrow() {
            imp.initial_value.borrow().clone()
        } else {
            builtins::get_current_theme_value(setting_id, &self.mode())
        };
        let mut selected = gtk::INVALID_LIST_POSITION;
        for (i, value) in value_ids.iter().enumerate() {
            if *value == current {
                selected = i as u32;
            }
        }
        if selected == gtk::INVALID_LIST_POSITION && !current.is_empty() {
            // Keep a value that discovery did not find
            model.append(&builtins::get_setting_value_label(setting_id, &current));
            value_ids.push(current);
            selected = value_ids.len() as u32 - 1;
        }
        *imp.value_ids.borrow_mut() = value_ids;

        // Long package ids are shown by their desktop names. The tooltip
        // still gives the full text when the label is clipped.
        let value_row = imp.value_row.get().unwrap();
        value_row.set_model(Some(&model));
        value_row.set_factory(Some(&create_value_factory()));
        value_row.set_list_factory(Some(&create_value_factory()));
        value_row.set_selected(selected);

        let supported = setting_id != "shell-theme" || builtins::has_shell_theme_support();
        value_row.set_sensitive(supported);
        value_row.set_subtitle(&if supported {
            String::new()
        } else {
            gettext("Requires the User Themes GNOME Shell extension.")
        });
    }

    fn get_selected_value(&self) -> String {
        let imp = self.imp();
        let selected = imp.value_row.get().unwrap().selected();
        let value_ids = imp.value_ids.borrow();
        if selected == gtk::INVALID_LIST_POSITION || selected as usize >= value_ids.len() {
            return String::new();
        }
        value_ids[selected as usize].clone()
    }

    fn buffer_text(&self) -> String {
        let buffer = self.imp().command_buffer.get().unwrap();
        // The text property, which leaves out hidden characters
        buffer
            .text(&buffer.start_iter(), &buffer.end_iter(), false)
            .to_string()
    }

    fn update_save_response(&self) {
        let imp = self.imp();
        let setting_id = self.get_setting_id();
        let valid = if setting_id.is_empty() {
            !util::strip(&self.buffer_text()).is_empty()
        } else if builtins::is_image_setting(&setting_id) {
            !imp.wallpaper_path.borrow().is_empty()
        } else {
            imp.value_row.get().unwrap().is_sensitive() && !self.get_selected_value().is_empty()
        };

        // Disabled commands do not run, so they cannot loop
        let entry = imp.entry.borrow().clone();
        let mut conflict = None;
        if valid && entry.as_ref().is_none_or(|e| e.enabled()) {
            conflict = builtins::find_loop_conflict(&self.get_command(), &self.mode());
        }
        let duplicate = if valid {
            builtins::find_duplicate(
                &imp.commands.borrow(),
                entry.as_ref(),
                &self.get_command(),
                &setting_id,
                &self.mode(),
            )
        } else {
            None
        };

        let conflict_label = imp.conflict_label.get().unwrap();
        conflict_label.set_label(conflict.as_deref().unwrap_or(""));
        conflict_label.set_visible(conflict.is_some());
        let duplicate_label = imp.duplicate_label.get().unwrap();
        duplicate_label.set_label(duplicate.as_deref().unwrap_or(""));
        duplicate_label.set_visible(duplicate.is_some());
        self.set_response_enabled("save", valid && conflict.is_none());
    }

    // The command Save stores
    fn get_command(&self) -> String {
        let setting_id = self.get_setting_id();
        if setting_id.is_empty() {
            return util::strip(&self.buffer_text()).to_string();
        }
        let value = if builtins::is_image_setting(&setting_id) {
            self.imp().wallpaper_path.borrow().clone()
        } else {
            self.get_selected_value()
        };
        builtins::build_builtin_command(&setting_id, &value)
    }

    fn update_test_button(&self) {
        let imp = self.imp();
        imp.test_button.get().unwrap().set_sensitive(
            imp.test_cancellable.borrow().is_none() && !util::strip(&self.buffer_text()).is_empty(),
        );
    }

    fn on_test_command(&self) {
        let imp = self.imp();
        self.show_test_result(false, None);
        let cancellable = gio::Cancellable::new();
        *imp.test_cancellable.borrow_mut() = Some(cancellable.clone());
        imp.test_spinner.get().unwrap().set_visible(true);
        self.update_test_button();

        let command = util::strip(&self.buffer_text()).to_string();
        runner::test_command(
            &command,
            &cancellable,
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |result| {
                    let error_text = match result {
                        Err(e) if e.matches(gio::IOErrorEnum::Cancelled) => return,
                        Err(e) => Some(e.message().to_string()),
                        Ok(error_text) => error_text,
                    };
                    let imp = obj.imp();
                    *imp.test_cancellable.borrow_mut() = None;
                    imp.test_spinner.get().unwrap().set_visible(false);
                    obj.update_test_button();
                    obj.show_test_result(true, error_text.as_deref());
                }
            ),
        );
    }

    // Shows nothing when not finished, else success or the error text
    fn show_test_result(&self, finished: bool, error_text: Option<&str>) {
        let imp = self.imp();
        let failed = finished && error_text.is_some();
        if failed {
            glib::g_print!("{}\n", error_text.unwrap());
        }
        let test_status = imp.test_status.get().unwrap();
        test_status.remove_css_class("success");
        test_status.remove_css_class("error");
        if finished {
            test_status.add_css_class(if failed { "error" } else { "success" });
        }
        test_status.set_label(&if !finished {
            String::new()
        } else if failed {
            gettext("Command failed")
        } else {
            gettext("Command succeeded")
        });
        imp.error_label
            .get()
            .unwrap()
            .set_text(if failed { error_text.unwrap() } else { "" });
        imp.error_box.get().unwrap().set_visible(failed);
    }

    fn set_wallpaper(&self, path: &str) {
        let imp = self.imp();
        *imp.wallpaper_path.borrow_mut() = path.to_string();
        let image_label = imp.image_label.get().unwrap();
        image_label.set_label(&if path.is_empty() {
            String::new()
        } else {
            util::basename(path)
        });
        image_label.set_tooltip_text(if path.is_empty() { None } else { Some(path) });
    }

    fn on_browse_wallpaper(&self) {
        let dialog = gtk::FileDialog::new();
        dialog.set_title(&gettext("Select Wallpaper"));

        let filter = gtk::FileFilter::new();
        filter.add_mime_type("image/*");
        let filters = gio::ListStore::new::<gtk::FileFilter>();
        filters.append(&filter);
        dialog.set_filters(Some(&filters));
        dialog.set_default_filter(Some(&filter));

        let parent = self.root().and_downcast::<gtk::Window>();
        dialog.open(
            parent.as_ref(),
            gio::Cancellable::NONE,
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |result| {
                    // Errors mean cancelled
                    if let Ok(file) = result
                        && let Some(path) = file.path().map(|p| p.to_string_lossy().into_owned())
                        && !path.is_empty()
                    {
                        obj.set_wallpaper(&path);
                        obj.update_save_response();
                    }
                }
            ),
        );
    }

    fn emit_saved(&self) {
        let imp = self.imp();
        let theme = self.mode();
        let setting_id = self.get_setting_id();
        let saved = imp.saved.borrow();
        let Some(saved) = saved.as_ref() else {
            return;
        };
        if setting_id.is_empty() {
            saved(util::strip(&self.buffer_text()), "", "", &theme);
            return;
        }

        let value = if builtins::is_image_setting(&setting_id) {
            imp.wallpaper_path.borrow().clone()
        } else {
            self.get_selected_value()
        };
        saved(
            &builtins::build_builtin_command(&setting_id, &value),
            &setting_id,
            &value,
            &theme,
        );
    }
}

fn create_value_factory() -> gtk::ListItemFactory {
    let factory = gtk::SignalListItemFactory::new();
    factory.connect_setup(|_, object| {
        let Some(item) = object.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let label = gtk::Label::new(None);
        label.set_xalign(0.0);
        label.set_ellipsize(pango::EllipsizeMode::End);
        label.set_max_width_chars(60);
        item.set_child(Some(&label));
    });
    factory.connect_bind(|_, object| {
        let Some(item) = object.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let label = item.child().and_downcast::<gtk::Label>();
        let string_object = item.item().and_downcast::<gtk::StringObject>();
        let (Some(label), Some(string_object)) = (label, string_object) else {
            return;
        };
        let text = string_object.string();
        label.set_label(&text);
        label.set_tooltip_text(Some(&text));
    });
    factory.upcast()
}
