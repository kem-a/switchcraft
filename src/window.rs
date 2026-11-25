// Main application window

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gdk, gio, glib, graphene};
use std::cell::{Cell, OnceCell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

use crate::application::Application;
use crate::builtins;
use crate::command_dialog::CommandDialog;
use crate::constants_window::ConstantsWindow;
use crate::i18n::gettext;
use crate::preferences::PreferencesWindow;
use crate::store::{self, CommandEntry, Commands};
use crate::util;
use crate::widgets::{AnimatedRows, SlidingToggleGroup};

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct MainWindow {
        pub commands: RefCell<Commands>,
        pub preferences_window: RefCell<Option<PreferencesWindow>>,
        pub toast_overlay: OnceCell<adw::ToastOverlay>,
        pub monitor_switch: OnceCell<gtk::Switch>,
        pub content_stack: OnceCell<gtk::Stack>,
        pub enabled_command_listbox: OnceCell<gtk::ListBox>,
        pub disabled_command_listbox: OnceCell<gtk::ListBox>,
        pub enabled_section: OnceCell<gtk::Widget>,
        pub disabled_section: OnceCell<gtk::Widget>,
        pub animated_rows: OnceCell<AnimatedRows>,
        pub command_row_entries: RefCell<HashMap<gtk::ListBoxRow, CommandEntry>>,
        pub drag_source_entry: RefCell<Option<CommandEntry>>,
        pub drag_theme: RefCell<Option<String>>,
        pub drag_source_enabled: Cell<bool>,
        pub row_theme_map: RefCell<Vec<String>>,
        pub row_entry_map: RefCell<Vec<CommandEntry>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for MainWindow {
        const NAME: &'static str = "SwitchcraftMainWindow";
        type Type = super::MainWindow;
        type ParentType = adw::ApplicationWindow;
    }

    impl ObjectImpl for MainWindow {}
    impl WidgetImpl for MainWindow {}
    impl WindowImpl for MainWindow {}
    impl ApplicationWindowImpl for MainWindow {}
    impl AdwApplicationWindowImpl for MainWindow {}
}

glib::wrapper! {
    pub struct MainWindow(ObjectSubclass<imp::MainWindow>)
        @extends adw::ApplicationWindow, gtk::ApplicationWindow, gtk::Window, gtk::Widget,
        @implements gio::ActionGroup, gio::ActionMap, gtk::Accessible, gtk::Buildable,
                    gtk::ConstraintTarget, gtk::Native, gtk::Root, gtk::ShortcutManager;
}

impl MainWindow {
    pub fn new(app: &Application) -> Self {
        let obj: Self = glib::Object::builder().property("application", app).build();

        obj.set_title(Some("Switchcraft"));
        obj.set_default_size(850, 620);
        obj.set_size_request(360, 294);

        obj.load_commands_from_application();

        obj.build_ui();
        obj
    }

    fn app(&self) -> Option<Application> {
        self.application().and_downcast::<Application>()
    }

    fn toast_overlay(&self) -> &adw::ToastOverlay {
        self.imp().toast_overlay.get().unwrap()
    }

    fn build_ui(&self) {
        let imp = self.imp();
        let toolbar_view = adw::ToolbarView::new();
        let header_bar = adw::HeaderBar::new();
        toolbar_view.add_top_bar(&header_bar);

        // Add actions
        self.add_action_handler("add-command", |win| win.on_add_command_action());
        self.add_action_handler("show-preferences", |win| win.on_show_preferences_action());
        self.add_action_handler("show-about", |win| win.on_show_about_action());
        self.add_action_handler("show-constants", |win| win.on_show_constants_action());

        let add_button = gtk::Button::from_icon_name("list-add-symbolic");
        add_button.set_tooltip_text(Some(&gettext("Add Command")));
        add_button.set_action_name(Some("win.add-command"));
        header_bar.pack_start(&add_button);

        // Menu button
        let menu_button = gtk::MenuButton::new();
        menu_button.set_icon_name("open-menu-symbolic");
        let menu = gio::Menu::new();
        menu.append(Some(&gettext("Preferences")), Some("win.show-preferences"));
        menu.append(Some(&gettext("Constants")), Some("win.show-constants"));
        // app.shortcuts comes from Adw.Application and shortcuts-dialog.ui
        menu.append(Some(&gettext("Keyboard Shortcuts")), Some("app.shortcuts"));
        menu.append(Some(&gettext("About Switchcraft")), Some("win.show-about"));
        menu.append(Some(&gettext("Quit")), Some("app.quit"));
        menu_button.set_menu_model(Some(&menu));
        header_bar.pack_end(&menu_button);

        // Background monitor switch, left of the menu
        let monitor_switch = gtk::Switch::new();
        monitor_switch.set_valign(gtk::Align::Center);
        monitor_switch.set_active(self.app().is_some_and(|app| app.get_monitoring_enabled()));
        monitor_switch.set_tooltip_text(Some(&gettext(
            "Run the background process that reacts to theme changes.",
        )));
        monitor_switch.update_property(&[gtk::accessible::Property::Label(&gettext("Monitor"))]);
        monitor_switch.connect_active_notify(glib::clone!(
            #[weak(rename_to = win)]
            self,
            move |_| win.on_monitor_switch_changed()
        ));
        imp.monitor_switch.set(monitor_switch.clone()).unwrap();
        let monitor_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        monitor_box.append(&gtk::Label::new(Some(&gettext("Monitor"))));
        monitor_box.append(&monitor_switch);
        header_bar.pack_end(&monitor_box);

        let placeholder = adw::StatusPage::new();
        placeholder.set_icon_name(Some("utilities-terminal-symbolic"));
        placeholder.set_title(&gettext("No Commands"));
        placeholder.set_description(Some(&gettext(
            "Use the '+' button in the header bar or press (Ctrl+N) to add a command.",
        )));

        let empty_add_content = adw::ButtonContent::new();
        empty_add_content.set_icon_name("list-add-symbolic");
        empty_add_content.set_label(&gettext("Add Command"));

        let empty_add_button = gtk::Button::new();
        empty_add_button.set_child(Some(&empty_add_content));
        empty_add_button.set_action_name(Some("win.add-command"));
        empty_add_button.add_css_class("pill");
        empty_add_button.add_css_class("suggested-action");
        empty_add_button.set_halign(gtk::Align::Center);
        placeholder.set_child(Some(&empty_add_button));

        let content_stack = gtk::Stack::new();
        content_stack.set_vexpand(true);
        content_stack.add_named(&self.build_command_list(), Some("list"));
        content_stack.add_named(&placeholder, Some("empty"));
        imp.content_stack.set(content_stack.clone()).unwrap();

        toolbar_view.set_content(Some(&content_stack));

        let toast_overlay = adw::ToastOverlay::new();
        toast_overlay.set_child(Some(&toolbar_view));
        self.set_content(Some(&toast_overlay));
        imp.toast_overlay.set(toast_overlay).unwrap();

        self.rebuild_display_order();
        self.refresh_command_list_ui();
    }

    // ── Command list ──────────────────────────────────────────────────

    fn build_command_list(&self) -> gtk::Widget {
        let imp = self.imp();
        let page_box = gtk::Box::new(gtk::Orientation::Vertical, 24);
        page_box.set_margin_top(24);
        page_box.set_margin_bottom(24);
        page_box.set_margin_start(24);
        page_box.set_margin_end(24);

        let (enabled_section, enabled_listbox) = create_section(
            &gettext("Commands"),
            &gettext("Active commands that will run when their theme matches."),
        );
        page_box.append(&enabled_section);

        let (disabled_section, disabled_listbox) = create_section(
            &gettext("Disabled"),
            &gettext("Saved commands that are currently turned off."),
        );
        page_box.append(&disabled_section);

        imp.enabled_section.set(enabled_section).unwrap();
        imp.disabled_section.set(disabled_section).unwrap();
        imp.enabled_command_listbox
            .set(enabled_listbox.clone())
            .unwrap();
        imp.disabled_command_listbox
            .set(disabled_listbox.clone())
            .unwrap();

        self.configure_listbox_for_reordering(&enabled_listbox);
        self.configure_listbox_for_reordering(&disabled_listbox);

        let weak = self.downgrade();
        let animated_rows = AnimatedRows::new(
            &page_box,
            &[enabled_listbox.upcast(), disabled_listbox.upcast()],
            Box::new(move |row| {
                let win = weak.upgrade()?;
                let row = row.downcast_ref::<gtk::ListBoxRow>()?;
                win.imp()
                    .command_row_entries
                    .borrow()
                    .get(row)
                    .map(CommandEntry::key)
            }),
        );
        imp.animated_rows.set(animated_rows.clone()).unwrap();

        let scrolled = gtk::ScrolledWindow::new();
        scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
        scrolled.set_hexpand(true);
        scrolled.set_vexpand(true);
        scrolled.set_child(Some(&animated_rows));

        scrolled.upcast()
    }

    fn rebuild_display_order(&self) {
        let imp = self.imp();
        let mut themes = Vec::new();
        let mut entries: Vec<CommandEntry> = Vec::new();

        {
            let commands = imp.commands.borrow();
            for theme in ["light", "dark"] {
                for e in commands.get(theme) {
                    themes.push(theme.to_string());
                    entries.push(e.clone());
                }
            }
        }

        // Restore the saved list order. Entries without a position keep the
        // light-then-dark order after the others.
        for i in 1..entries.len() {
            let mut j = i;
            while j > 0 && sort_position(&entries[j - 1]) > sort_position(&entries[j]) {
                entries.swap(j, j - 1);
                themes.swap(j, j - 1);
                j -= 1;
            }
        }

        *imp.row_theme_map.borrow_mut() = themes;
        *imp.row_entry_map.borrow_mut() = entries;
    }

    fn refresh_command_list_ui(&self) {
        let imp = self.imp();
        imp.animated_rows.get().unwrap().begin_reorder();
        imp.command_row_entries.borrow_mut().clear();
        let enabled_listbox = imp.enabled_command_listbox.get().unwrap();
        let disabled_listbox = imp.disabled_command_listbox.get().unwrap();
        clear_command_listbox(enabled_listbox);
        clear_command_listbox(disabled_listbox);

        let entries = imp.row_entry_map.borrow().clone();
        let themes = imp.row_theme_map.borrow().clone();
        for (entry, theme) in entries.iter().zip(themes.iter()) {
            let listbox = if entry.enabled() {
                enabled_listbox
            } else {
                disabled_listbox
            };
            listbox.append(&self.create_command_row(theme, entry));
        }

        // Empty boxed lists would draw as thin lines
        imp.enabled_section
            .get()
            .unwrap()
            .set_visible(enabled_listbox.row_at_index(0).is_some());
        imp.disabled_section
            .get()
            .unwrap()
            .set_visible(disabled_listbox.row_at_index(0).is_some());
        imp.content_stack
            .get()
            .unwrap()
            .set_visible_child_name(if entries.is_empty() { "empty" } else { "list" });
    }

    fn rebuild_commands_from_display_order(&self) {
        let imp = self.imp();
        let mut light = Vec::new();
        let mut dark = Vec::new();
        for (entry, theme) in imp
            .row_entry_map
            .borrow()
            .iter()
            .zip(imp.row_theme_map.borrow().iter())
        {
            if theme == "dark" {
                dark.push(entry.clone());
            } else {
                light.push(entry.clone());
            }
        }
        let mut commands = imp.commands.borrow_mut();
        commands.set("light", light);
        commands.set("dark", dark);
    }

    fn get_entry_index(&self, entry: &CommandEntry) -> i32 {
        self.imp()
            .row_entry_map
            .borrow()
            .iter()
            .position(|e| e == entry)
            .map_or(-1, |i| i as i32)
    }

    fn get_entry_theme(&self, entry: &CommandEntry) -> String {
        let index = self.get_entry_index(entry);
        if index >= 0 {
            return self.imp().row_theme_map.borrow()[index as usize].clone();
        }

        "light".to_string()
    }

    fn create_command_row(&self, theme: &str, entry: &CommandEntry) -> adw::ActionRow {
        let imp = self.imp();
        let row = adw::ActionRow::new();
        // Commands often contain & < > which are not valid markup
        row.set_use_markup(false);
        let builtin_title = builtins::get_builtin_title(&entry.builtin());
        if !builtin_title.is_empty() {
            // Built-in settings show the setting and value, not the gsettings line
            row.set_title(&builtin_title);
            row.set_subtitle(&if builtins::is_image_setting(&entry.builtin()) {
                util::basename(&entry.value())
            } else {
                builtins::get_setting_value_label(&entry.builtin(), &entry.value())
            });
            row.set_tooltip_text(Some(&entry.command()));
        } else {
            row.set_title(&entry.command());
        }
        imp.command_row_entries
            .borrow_mut()
            .insert(row.clone().upcast(), entry.clone());

        // Duplicates are allowed, but make them easy to spot
        let duplicate = builtins::find_duplicate(
            &imp.commands.borrow(),
            Some(entry),
            &entry.command(),
            &entry.builtin(),
            theme,
        );
        if let Some(duplicate) = duplicate {
            let duplicate_box = gtk::Box::new(gtk::Orientation::Horizontal, 4);
            duplicate_box.set_valign(gtk::Align::Center);
            duplicate_box.set_tooltip_text(Some(&duplicate));

            let duplicate_icon = gtk::Image::from_icon_name("dialog-warning-symbolic");
            duplicate_icon.add_css_class("warning");
            let duplicate_text = gtk::Label::new(Some(&gettext("Duplicate")));
            duplicate_text.add_css_class("caption");
            duplicate_text.add_css_class("warning");

            duplicate_box.append(&duplicate_icon);
            duplicate_box.append(&duplicate_text);
            row.add_suffix(&duplicate_box);
        }

        // Drag handle
        let drag_handle = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        drag_handle.set_valign(gtk::Align::Center);
        drag_handle.set_margin_end(6);
        drag_handle.set_tooltip_text(Some(&gettext("Drag to reorder")));

        let drag_icon = gtk::Image::from_icon_name("list-drag-handle-symbolic");
        drag_icon.add_css_class("dim-label");
        drag_handle.append(&drag_icon);

        let drag_source = gtk::DragSource::new();
        drag_source.set_actions(gdk::DragAction::MOVE);
        let press = Rc::new(Cell::new((0.0, 0.0)));
        drag_source.connect_prepare(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            #[strong]
            press,
            #[upgrade_or]
            None,
            move |_, x, y| {
                press.set((x, y));
                if win.get_entry_index(&entry) < 0 {
                    win.reset_drag_state();
                    return None;
                }

                let imp = win.imp();
                let drag_theme = win.get_entry_theme(&entry);
                *imp.drag_source_entry.borrow_mut() = Some(entry.clone());
                *imp.drag_theme.borrow_mut() = Some(drag_theme.clone());
                imp.drag_source_enabled.set(entry.enabled());

                Some(gdk::ContentProvider::for_value(&drag_theme.to_value()))
            }
        ));
        drag_source.connect_drag_begin(glib::clone!(
            #[weak]
            row,
            #[weak]
            drag_handle,
            #[strong]
            press,
            move |_, drag| {
                let (x, y) = press.get();
                set_drag_icon(drag, &row, drag_handle.upcast_ref(), x, y);
            }
        ));
        drag_source.connect_drag_end(glib::clone!(
            #[weak(rename_to = win)]
            self,
            move |_, _, _| win.reset_drag_state()
        ));
        drag_source.connect_drag_cancel(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[upgrade_or]
            false,
            move |_, _, _| {
                win.reset_drag_state();
                false
            }
        ));
        drag_handle.add_controller(drag_source);

        // Theme toggle group (light / dark). Initial state is set before
        // connecting to avoid a spurious change.
        let theme_toggle = SlidingToggleGroup::for_theme(theme);
        theme_toggle.set_margin_end(6);
        let group = theme_toggle.group();
        group.connect_active_name_notify(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move |group| {
                let name = group
                    .active_name()
                    .map(|n| n.to_string())
                    .unwrap_or_default();
                if !win.on_theme_toggle_changed(&entry, &name) {
                    // Slides back to the mode the command stays in
                    group.set_active_name(Some(&win.get_entry_theme(&entry)));
                }
            }
        ));
        row.add_prefix(&theme_toggle);
        // Prefixes are prepended, so the handle added last sits first
        row.add_prefix(&drag_handle);

        // Clicking the row opens the edit dialog
        row.set_activatable(true);
        row.connect_activated(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move |_| win.show_command_dialog(Some(entry.clone()))
        ));

        // Enable/disable switch
        let enable_switch = gtk::Switch::new();
        enable_switch.set_valign(gtk::Align::Center);
        enable_switch.set_active(entry.enabled());
        enable_switch.connect_active_notify(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move |enable_switch| {
                let active = enable_switch.is_active();
                if active == entry.enabled() {
                    return;
                }
                if active && !win.check_conflict(&entry, &win.get_entry_theme(&entry)) {
                    enable_switch.set_active(false);
                    return;
                }
                win.on_toggle_command_state(active, &entry);
            }
        ));
        row.add_suffix(&enable_switch);

        update_row_state(&row, entry);

        row
    }

    fn show_command_dialog(&self, entry: Option<CommandEntry>) {
        if self.app().is_none() {
            return;
        }

        let theme = entry
            .as_ref()
            .map_or("light".to_string(), |e| self.get_entry_theme(e));
        let dialog =
            CommandDialog::new(self.imp().commands.borrow().clone(), entry.clone(), &theme);
        dialog.connect_saved(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move |command, builtin, value, theme| {
                win.save_command(entry.as_ref(), command, builtin, value, theme);
            }
        ));
        dialog.connect_deleted(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move || {
                if let Some(entry) = &entry {
                    win.on_remove_command_clicked(entry);
                }
            }
        ));
        dialog.present(Some(self));
    }

    fn save_command(
        &self,
        entry: Option<&CommandEntry>,
        command: &str,
        builtin: &str,
        value: &str,
        theme: &str,
    ) {
        let imp = self.imp();
        match entry {
            None => {
                imp.row_theme_map.borrow_mut().push(theme.to_string());
                imp.row_entry_map
                    .borrow_mut()
                    .push(CommandEntry::with_builtin(command, builtin, value));
            }
            Some(entry) => {
                let index = self.get_entry_index(entry);
                if index < 0 {
                    return;
                }
                entry.set_command(command);
                entry.set_builtin(builtin);
                entry.set_value(value);
                imp.row_theme_map.borrow_mut()[index as usize] = theme.to_string();
            }
        }

        self.rebuild_commands_from_display_order();
        self.save_commands();
        self.refresh_command_list_ui();
    }

    // Returns false when the command cannot move to new_theme
    fn on_theme_toggle_changed(&self, entry: &CommandEntry, new_theme: &str) -> bool {
        let listbox_index = self.get_entry_index(entry);
        if listbox_index < 0
            || self.imp().row_theme_map.borrow()[listbox_index as usize] == new_theme
        {
            return true;
        }
        if entry.enabled() && !self.check_conflict(entry, new_theme) {
            return false;
        }

        // The row keeps its place and its toggle slides, so no rebuild
        self.imp().row_theme_map.borrow_mut()[listbox_index as usize] = new_theme.to_string();
        self.rebuild_commands_from_display_order();
        self.save_commands();
        true
    }

    // Shows a toast when the command cannot run in the theme's list
    fn check_conflict(&self, entry: &CommandEntry, theme: &str) -> bool {
        let conflict = builtins::find_loop_conflict(&entry.command(), theme);
        if let Some(conflict) = &conflict {
            self.toast_overlay().add_toast(adw::Toast::new(conflict));
        }
        conflict.is_none()
    }

    fn on_toggle_command_state(&self, state: bool, entry: &CommandEntry) {
        entry.set_enabled(state);
        // A newly disabled row goes to the top of the Disabled list
        let index = self.get_entry_index(entry);
        if !state {
            let first_disabled = self.imp().row_entry_map.borrow()[..index.max(0) as usize]
                .iter()
                .position(|e| !e.enabled());
            if let Some(i) = first_disabled {
                self.reorder_display_command(index, i as i32);
                return;
            }
        }
        self.save_commands();
        // The row slides into the other section
        self.refresh_command_list_ui();
    }

    // ── Drag-and-drop reordering ──────────────────────────────────────

    fn configure_listbox_for_reordering(&self, listbox: &gtk::ListBox) {
        let drop_target = gtk::DropTarget::new(glib::Type::STRING, gdk::DragAction::MOVE);

        drop_target.connect_accept(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[upgrade_or]
            false,
            move |_, _| {
                let imp = win.imp();
                imp.drag_theme.borrow().is_some() && imp.drag_source_entry.borrow().is_some()
            }
        ));

        drop_target.connect_enter(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[weak]
            listbox,
            #[upgrade_or]
            gdk::DragAction::empty(),
            move |_, _, y| {
                if win.highlight_drop_position(&listbox, y) {
                    gdk::DragAction::MOVE
                } else {
                    gdk::DragAction::empty()
                }
            }
        ));

        drop_target.connect_motion(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[weak]
            listbox,
            #[upgrade_or]
            gdk::DragAction::empty(),
            move |_, _, y| {
                if win.highlight_drop_position(&listbox, y) {
                    gdk::DragAction::MOVE
                } else {
                    gdk::DragAction::empty()
                }
            }
        ));

        drop_target.connect_leave(glib::clone!(
            #[weak]
            listbox,
            move |_| listbox.drag_unhighlight_row()
        ));

        drop_target.connect_drop(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[weak]
            listbox,
            #[upgrade_or]
            false,
            move |_, _, _, y| {
                listbox.drag_unhighlight_row();

                let imp = win.imp();
                let source_entry = imp.drag_source_entry.borrow().clone();
                let (Some(source_entry), true) = (source_entry, imp.drag_theme.borrow().is_some())
                else {
                    win.reset_drag_state();
                    return false;
                };

                let source_enabled = imp.drag_source_enabled.get();
                win.reset_drag_state();

                let Some(target_row) = listbox.row_at_y(y as i32) else {
                    return false;
                };

                let source_display_idx = win.get_entry_index(&source_entry);
                let target_display_idx = win.get_drop_index(&target_row, source_enabled);
                if source_display_idx < 0 || target_display_idx < 0 {
                    return false;
                }

                win.reorder_display_command(source_display_idx, target_display_idx);
                true
            }
        ));

        listbox.add_controller(drop_target);
    }

    // Returns whether a drop at y would be accepted
    fn highlight_drop_position(&self, listbox: &gtk::ListBox, y: f64) -> bool {
        let row = listbox.row_at_y(y as i32);
        if self.imp().drag_source_entry.borrow().is_some()
            && let Some(row) = row
            && self.get_drop_index(&row, self.imp().drag_source_enabled.get()) >= 0
        {
            listbox.drag_highlight_row(&row);
            return true;
        }
        listbox.drag_unhighlight_row();
        false
    }

    // Index the dragged row moves to, or -1. Light and dark rows share one
    // ordered list, so any row of the same list is a target.
    fn get_drop_index(&self, row: &gtk::ListBoxRow, source_enabled: bool) -> i32 {
        let entry = self.imp().command_row_entries.borrow().get(row).cloned();
        match entry {
            Some(entry) if entry.enabled() == source_enabled => self.get_entry_index(&entry),
            _ => -1,
        }
    }

    fn reorder_display_command(&self, source_idx: i32, target_idx: i32) {
        let imp = self.imp();
        {
            let mut themes = imp.row_theme_map.borrow_mut();
            let mut entries = imp.row_entry_map.borrow_mut();
            let len = entries.len() as i32;
            if source_idx < 0 || target_idx < 0 || source_idx >= len || target_idx >= len {
                return;
            }
            if source_idx == target_idx {
                return;
            }

            let (source, target) = (source_idx as usize, target_idx as usize);
            let moved_theme = themes.remove(source);
            let moved_entry = entries.remove(source);
            themes.insert(target, moved_theme);
            entries.insert(target, moved_entry);
        }

        self.rebuild_commands_from_display_order();
        self.save_commands();
        self.refresh_command_list_ui();
    }

    fn reset_drag_state(&self) {
        let imp = self.imp();
        *imp.drag_source_entry.borrow_mut() = None;
        *imp.drag_theme.borrow_mut() = None;
        imp.drag_source_enabled.set(false);
    }

    // ── Command actions ───────────────────────────────────────────────

    fn on_add_command_action(&self) {
        self.show_command_dialog(None);
    }

    fn on_remove_command_clicked(&self, entry: &CommandEntry) {
        let imp = self.imp();
        let listbox_index = self.get_entry_index(entry);
        if listbox_index < 0 {
            return;
        }

        let theme = imp
            .row_theme_map
            .borrow_mut()
            .remove(listbox_index as usize);
        imp.row_entry_map
            .borrow_mut()
            .remove(listbox_index as usize);

        self.rebuild_commands_from_display_order();
        self.save_commands();
        self.refresh_command_list_ui();

        let toast = adw::Toast::new(&gettext("Command deleted"));
        toast.set_button_label(Some(&gettext("Undo")));
        toast.connect_button_clicked(glib::clone!(
            #[weak(rename_to = win)]
            self,
            #[strong]
            entry,
            move |_| {
                let imp = win.imp();
                // The list may have shrunk since, so clamp the old position
                let index = (listbox_index as usize).min(imp.row_entry_map.borrow().len());
                imp.row_theme_map.borrow_mut().insert(index, theme.clone());
                imp.row_entry_map.borrow_mut().insert(index, entry.clone());

                win.rebuild_commands_from_display_order();
                win.save_commands();
                win.refresh_command_list_ui();
            }
        ));
        self.toast_overlay().add_toast(toast);
    }

    // ── Actions ───────────────────────────────────────────────────────

    fn add_action_handler(&self, name: &str, callback: fn(&Self)) {
        let action = gio::SimpleAction::new(name, None);
        action.connect_activate(glib::clone!(
            #[weak(rename_to = win)]
            self,
            move |_, _| callback(&win)
        ));
        self.add_action(&action);
    }

    fn on_show_preferences_action(&self) {
        if self.app().is_none() {
            return;
        }

        let preferences_window = self
            .imp()
            .preferences_window
            .borrow_mut()
            .get_or_insert_with(|| PreferencesWindow::new(self))
            .clone();

        preferences_window.present(Some(self));
    }

    fn on_show_about_action(&self) {
        let dialog = adw::AboutDialog::from_appdata(
            "/com/github/Switchcraft/com.github.Switchcraft.metainfo.xml",
            Some("com.github"),
        );
        // Found in the GResource icons folder, also when run from source
        dialog.set_application_icon("com.github.Switchcraft");

        let credits = [format!(
            "{} https://github.com/kem-a/switchcraft/graphs/contributors",
            gettext("Contributors")
        )];
        let credits: Vec<&str> = credits.iter().map(String::as_str).collect();
        dialog.add_credit_section(Some(&gettext("Credits")), &credits);

        dialog.present(Some(self));
    }

    fn on_show_constants_action(&self) {
        if self.app().is_none() {
            return;
        }

        let constants_window = ConstantsWindow::new(self.upcast_ref());
        constants_window.present();
    }

    // ── Persistence ───────────────────────────────────────────────────

    fn save_commands(&self) {
        if self.app().is_none() {
            return;
        }
        // Keeps the mixed light and dark order across restarts
        for (i, entry) in self.imp().row_entry_map.borrow().iter().enumerate() {
            entry.set_position(i as i32);
        }
        store::save_commands(&self.imp().commands.borrow());
    }

    pub fn reload_commands_from_storage(&self) {
        // Entries are recreated, so a drag would point at old ones
        self.reset_drag_state();
        self.load_commands_from_application();
        self.rebuild_display_order();
        self.refresh_command_list_ui();
    }

    // Turns the header switch, which starts or stops the monitor
    pub fn apply_monitoring_state(&self, enabled: bool) {
        self.imp().monitor_switch.get().unwrap().set_active(enabled);
    }

    fn on_monitor_switch_changed(&self) {
        let Some(app) = self.app() else {
            return;
        };

        let enabled = self.imp().monitor_switch.get().unwrap().is_active();
        if app.get_monitoring_enabled() == enabled {
            return;
        }

        app.set_monitoring_enabled(enabled);
        self.show_toast(
            &if enabled {
                gettext("Background monitoring is now active")
            } else {
                gettext("Background monitoring is now inactive")
            },
            false,
        );
    }

    pub fn show_toast(&self, message: &str, is_error: bool) {
        let toast = adw::Toast::new(message);
        if is_error {
            toast.set_priority(adw::ToastPriority::High);
        }
        self.toast_overlay().add_toast(toast);
    }

    fn load_commands_from_application(&self) {
        *self.imp().commands.borrow_mut() = store::get_commands();
    }
}

fn create_section(title: &str, description: &str) -> (gtk::Widget, gtk::ListBox) {
    let section_box = gtk::Box::new(gtk::Orientation::Vertical, 8);

    let title_label = gtk::Label::new(Some(title));
    title_label.add_css_class("title-4");
    title_label.set_xalign(0.0);
    section_box.append(&title_label);

    let description_label = gtk::Label::new(Some(description));
    description_label.add_css_class("dim-label");
    description_label.set_wrap(true);
    description_label.set_xalign(0.0);
    section_box.append(&description_label);

    let listbox = gtk::ListBox::new();
    listbox.set_selection_mode(gtk::SelectionMode::None);
    listbox.add_css_class("boxed-list");
    section_box.append(&listbox);

    (section_box.upcast(), listbox)
}

fn sort_position(entry: &CommandEntry) -> i32 {
    if entry.position() < 0 {
        i32::MAX
    } else {
        entry.position()
    }
}

fn clear_command_listbox(listbox: &gtk::ListBox) {
    while let Some(row) = listbox.row_at_index(0) {
        listbox.remove(&row);
    }
}

fn update_row_state(row: &adw::ActionRow, entry: &CommandEntry) {
    if entry.enabled() {
        row.remove_css_class("dim-label");
    } else {
        row.add_css_class("dim-label");
    }
}

fn set_drag_icon(
    drag: &gdk::Drag,
    row: &adw::ActionRow,
    handle: &gtk::Widget,
    press_x: f64,
    press_y: f64,
) {
    // Show a copy of the row while dragging. A plain list is opaque,
    // boxed-list cards are translucent in dark mode.
    let copy = adw::ActionRow::new();
    copy.set_use_markup(false);
    copy.set_title(&row.title());
    copy.set_subtitle(&row.subtitle().unwrap_or_default());
    copy.add_prefix(&gtk::Image::from_icon_name("list-drag-handle-symbolic"));

    let list = gtk::ListBox::new();
    list.set_size_request(row.width(), row.height());
    list.append(&copy);
    list.drag_highlight_row(&copy);

    let icon = gtk::DragIcon::for_drag(drag);
    icon.set_child(Some(&list));

    // Keep the pointer where the drag started
    let hotspot = handle
        .compute_point(row, &graphene::Point::new(press_x as f32, press_y as f32))
        .unwrap_or_else(|| graphene::Point::new(0.0, 0.0));
    drag.set_hotspot(hotspot.x() as i32, hotspot.y() as i32);
}
