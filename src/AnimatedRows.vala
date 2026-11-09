/* AnimatedRows.vala
 * Slides list rows from their old to their new position after a rebuild
 *
 * Copyright (c) 2026 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    // Ported from AppManager's AnimatedAppView. Rows are matched across
    // rebuilds by the pointer stored under ROW_KEY with set_data.
    public class AnimatedRows : Gtk.Widget {
        public const string ROW_KEY = "animation-key";

        [Compact]
        private class Position {
            public float x;
            public float y;

            public Position (float x, float y) {
                this.x = x;
                this.y = y;
            }
        }

        private Gtk.Widget child;
        // Lists whose rows are animated. Positions are compared in child,
        // so rows can slide from one list into another.
        private Gtk.Widget[] containers;
        private HashTable<void*, Position> previous_positions;
        private HashTable<void*, Position> offsets;
        private Adw.TimedAnimation animation;
        private double progress = 1;
        private bool reorder_pending = false;

        public AnimatedRows (Gtk.Widget child, Gtk.Widget[] containers) {
            this.child = child;
            this.containers = containers;
            previous_positions = new HashTable<void*, Position> (direct_hash, direct_equal);
            offsets = new HashTable<void*, Position> (direct_hash, direct_equal);
            child.set_parent (this);

            weak AnimatedRows view = this;
            var target = new Adw.CallbackAnimationTarget ((value) => {
                view.progress = value;
                view.queue_allocate ();
            });
            animation = new Adw.TimedAnimation (this, 0, 1, 300, target);
            animation.easing = Adw.Easing.EASE_OUT_CUBIC;
            animation.done.connect (() => {
                view.offsets.remove_all ();
                view.queue_allocate ();
            });
        }

        // Call before the rows are rebuilt
        public void begin_reorder () {
            // Several rebuilds can happen before the next allocation.
            // Keep the last visible positions.
            if (reorder_pending) {
                return;
            }

            previous_positions.remove_all ();
            if (get_mapped () && Adw.get_enable_animations (this)) {
                foreach (var row in tracked_rows ()) {
                    void* key = row.get_data<void*> (ROW_KEY);
                    var bounds = Graphene.Rect ();
                    if (key == null || !row.compute_bounds (child, out bounds)) {
                        continue;
                    }
                    previous_positions.insert (key, new Position (bounds.origin.x, bounds.origin.y));
                }
            }

            animation.reset ();
            offsets.remove_all ();
            reorder_pending = previous_positions.size () > 0;
        }

        private List<unowned Gtk.Widget> tracked_rows () {
            var rows = new List<unowned Gtk.Widget> ();
            foreach (var container in containers) {
                for (var row = container.get_first_child (); row != null; row = row.get_next_sibling ()) {
                    rows.append (row);
                }
            }
            return rows;
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return child.get_request_mode ();
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            child.measure (orientation, for_size, out minimum, out natural,
                out minimum_baseline, out natural_baseline);
        }

        public override void size_allocate (int width, int height, int baseline) {
            // Reset the lists to their natural allocations before applying
            // this frame's transforms. Moving allocations also keeps pointer
            // picking and focus outlines aligned with the animated rows.
            foreach (var container in containers) {
                container.queue_allocate ();
            }
            child.allocate (width, height, baseline, null);

            if (!Adw.get_enable_animations (this)) {
                animation.skip ();
                previous_positions.remove_all ();
                offsets.remove_all ();
                reorder_pending = false;
                return;
            }

            bool start_animation = reorder_pending;
            reorder_pending = false;
            foreach (var row in tracked_rows ()) {
                void* key = row.get_data<void*> (ROW_KEY);
                var bounds = Graphene.Rect ();
                if (key == null || !row.compute_bounds (child, out bounds)) {
                    continue;
                }

                if (start_animation) {
                    unowned Position? previous = previous_positions.lookup (key);
                    if (previous != null) {
                        float dx = previous.x - bounds.origin.x;
                        float dy = previous.y - bounds.origin.y;
                        if (dx.abs () > 0.5f || dy.abs () > 0.5f) {
                            offsets.insert (key, new Position (dx, dy));
                        }
                    }
                }

                unowned Position? offset = offsets.lookup (key);
                if (offset != null) {
                    float remaining = start_animation ? 1 : (float) (1 - progress);
                    // The transform is relative to the row's own list
                    var local = Graphene.Rect ();
                    row.compute_bounds (row.get_parent (), out local);
                    var transform = new Gsk.Transform ().translate (Graphene.Point () {
                        x = local.origin.x + offset.x * remaining,
                        y = local.origin.y + offset.y * remaining
                    });
                    row.allocate ((int) bounds.size.width, (int) bounds.size.height, -1, transform);
                }
            }

            previous_positions.remove_all ();
            if (start_animation && offsets.size () > 0) {
                animation.play ();
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            snapshot_child (child, snapshot);
        }

        public override void unmap () {
            animation.skip ();
            previous_positions.remove_all ();
            offsets.remove_all ();
            reorder_pending = false;
            base.unmap ();
        }

        protected override void dispose () {
            if (child != null && child.get_parent () == this) {
                child.unparent ();
            }
            base.dispose ();
        }
    }
}
