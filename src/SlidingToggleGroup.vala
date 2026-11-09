/* SlidingToggleGroup.vala
 * Adw.ToggleGroup whose selection slides between toggles
 *
 * Copyright (c) 2026 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    // Draws the group background and a checked toggle below the real
    // Adw.ToggleGroup, which style.css makes transparent. Both use the
    // toggle-group CSS names, so they follow the libadwaita theme.
    public class SlidingToggleGroup : Gtk.Widget {
        private class Indicator : Gtk.Widget {
            static construct {
                set_css_name ("toggle");
            }

            construct {
                set_can_target (false);
                set_state_flags (Gtk.StateFlags.CHECKED, false);
            }
        }

        public Adw.ToggleGroup group { get; private set; }
        private Indicator indicator;
        private Adw.TimedAnimation animation;
        private Graphene.Rect from_rect;
        private Graphene.Rect current_rect;

        static construct {
            set_css_name ("toggle-group");
        }

        public SlidingToggleGroup (Adw.ToggleGroup group) {
            this.group = group;
            add_css_class ("round");
            add_css_class ("sliding");
            group.add_css_class ("round");

            indicator = new Indicator ();
            indicator.set_parent (this);
            group.set_parent (this);

            weak SlidingToggleGroup view = this;
            var target = new Adw.CallbackAnimationTarget ((value) => {
                view.queue_allocate ();
            });
            animation = new Adw.TimedAnimation (this, 0, 1, 250, target);
            animation.easing = Adw.Easing.EASE_OUT_CUBIC;

            group.notify["active"].connect (() => {
                view.from_rect = view.current_rect;
                view.animation.play ();
            });
        }

        private Gtk.Widget? get_active_toggle () {
            uint active = group.get_active ();
            uint index = 0;
            for (var child = group.get_first_child (); child != null; child = child.get_next_sibling ()) {
                // Toggles alternate with separators
                if (child is Gtk.Separator) {
                    continue;
                }
                if (index++ == active) {
                    return child;
                }
            }
            return null;
        }

        protected override Gtk.SizeRequestMode get_request_mode () {
            return group.get_request_mode ();
        }

        protected override void measure (Gtk.Orientation orientation, int for_size,
                                         out int minimum, out int natural,
                                         out int minimum_baseline, out int natural_baseline) {
            group.measure (orientation, for_size, out minimum, out natural,
                           out minimum_baseline, out natural_baseline);
        }

        protected override void size_allocate (int width, int height, int baseline) {
            group.allocate (width, height, baseline, null);

            var toggle = get_active_toggle ();
            var target = Graphene.Rect ();
            if (toggle == null || !toggle.compute_bounds (this, out target)) {
                indicator.set_child_visible (false);
                return;
            }
            indicator.set_child_visible (true);

            current_rect = animation.state == Adw.AnimationState.PLAYING
                ? from_rect.interpolate (target, animation.value)
                : target;

            var transform = new Gsk.Transform ().translate (
                Graphene.Point () { x = current_rect.origin.x, y = current_rect.origin.y });
            indicator.allocate ((int) (current_rect.size.width + 0.5f),
                                (int) (current_rect.size.height + 0.5f), -1, transform);
        }

        protected override void dispose () {
            if (indicator != null) {
                indicator.unparent ();
                indicator = null;
            }
            if (group != null) {
                group.unparent ();
            }
            base.dispose ();
        }
    }
}
