// Application entry point for Switchcraft
//
// Copyright (c) 2021-2026 kem-a
// SPDX-License-Identifier: GPL-3.0-or-later

mod application;
mod builtins;
mod bundle;
mod command_dialog;
mod config;
mod constants_window;
mod i18n;
mod json;
mod kde;
mod monitor;
mod preferences;
mod runner;
mod schedule;
mod spawn;
mod store;
mod util;
mod widgets;
mod window;

#[cfg(test)]
mod regression_tests;

use gtk::prelude::*;
use gtk::{gio, glib};

fn main() -> glib::ExitCode {
    i18n::init_i18n();
    gio::resources_register_include!("switchcraft.gresource").expect("registering the GResource");

    let app = application::Application::new();
    app.run()
}
