/* main.vala
 * Application entrypoint for Switchcraft
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public static int main (string[] args) {
        var app = new Application ();
        return app.run (args);
    }
}
