// Slides list rows from their old to their new position after a rebuild.
// Ported from AppManager's AnimatedAppView. Rows are matched across
// rebuilds by the key the key function gives for them.

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::glib;
use gtk::{graphene, gsk};
use std::cell::{Cell, OnceCell, RefCell};
use std::collections::HashMap;

pub type RowKeyFn = Box<dyn Fn(&gtk::Widget) -> Option<usize>>;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct AnimatedRows {
        pub child: OnceCell<gtk::Widget>,
        // Lists whose rows are animated. Positions are compared in child, so
        // rows can slide from one list into another.
        pub containers: OnceCell<Vec<gtk::Widget>>,
        pub row_key: OnceCell<RowKeyFn>,
        pub previous_positions: RefCell<HashMap<usize, (f32, f32)>>,
        pub offsets: RefCell<HashMap<usize, (f32, f32)>>,
        pub animation: OnceCell<adw::TimedAnimation>,
        pub progress: Cell<f64>,
        pub reorder_pending: Cell<bool>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for AnimatedRows {
        const NAME: &'static str = "SwitchcraftAnimatedRows";
        type Type = super::AnimatedRows;
        type ParentType = gtk::Widget;
    }

    impl ObjectImpl for AnimatedRows {
        fn dispose(&self) {
            if let Some(child) = self.child.get()
                && child.parent().as_ref() == Some(self.obj().upcast_ref())
            {
                child.unparent();
            }
        }
    }

    impl WidgetImpl for AnimatedRows {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            self.child().request_mode()
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            self.child().measure(orientation, for_size)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            let obj = self.obj();
            // Reset the lists to their natural allocations before applying
            // this frame's transforms. Moving allocations also keeps pointer
            // picking and focus outlines aligned with the animated rows.
            for container in self.containers.get().unwrap() {
                container.queue_allocate();
            }
            let child = self.child();
            child.allocate(width, height, baseline, None);

            let animation = self.animation.get().unwrap();
            if !adw::is_animations_enabled(&*obj) {
                animation.skip();
                self.previous_positions.borrow_mut().clear();
                self.offsets.borrow_mut().clear();
                self.reorder_pending.set(false);
                return;
            }

            let start_animation = self.reorder_pending.get();
            self.reorder_pending.set(false);
            for row in self.tracked_rows() {
                let Some(key) = (self.row_key.get().unwrap())(&row) else {
                    continue;
                };
                let Some(bounds) = row.compute_bounds(child) else {
                    continue;
                };

                if start_animation
                    && let Some((x, y)) = self.previous_positions.borrow().get(&key).copied()
                {
                    let dx = x - bounds.x();
                    let dy = y - bounds.y();
                    if dx.abs() > 0.5 || dy.abs() > 0.5 {
                        self.offsets.borrow_mut().insert(key, (dx, dy));
                    }
                }

                let offset = self.offsets.borrow().get(&key).copied();
                if let Some((dx, dy)) = offset {
                    let remaining = if start_animation {
                        1.0
                    } else {
                        (1.0 - self.progress.get()) as f32
                    };
                    // The transform is relative to the row's own list
                    let local = row
                        .parent()
                        .and_then(|parent| row.compute_bounds(&parent))
                        .unwrap_or_else(|| graphene::Rect::new(0.0, 0.0, 0.0, 0.0));
                    let transform = gsk::Transform::new().translate(&graphene::Point::new(
                        local.x() + dx * remaining,
                        local.y() + dy * remaining,
                    ));
                    row.allocate(
                        bounds.width() as i32,
                        bounds.height() as i32,
                        -1,
                        Some(transform),
                    );
                }
            }

            self.previous_positions.borrow_mut().clear();
            if start_animation && !self.offsets.borrow().is_empty() {
                animation.play();
            }
        }

        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            self.obj().snapshot_child(self.child(), snapshot);
        }

        fn unmap(&self) {
            self.animation.get().unwrap().skip();
            self.previous_positions.borrow_mut().clear();
            self.offsets.borrow_mut().clear();
            self.reorder_pending.set(false);
            self.parent_unmap();
        }
    }

    impl AnimatedRows {
        fn child(&self) -> &gtk::Widget {
            self.child.get().unwrap()
        }

        pub fn tracked_rows(&self) -> Vec<gtk::Widget> {
            let mut rows = Vec::new();
            for container in self.containers.get().unwrap() {
                let mut row = container.first_child();
                while let Some(widget) = row {
                    row = widget.next_sibling();
                    rows.push(widget);
                }
            }
            rows
        }
    }
}

glib::wrapper! {
    pub struct AnimatedRows(ObjectSubclass<imp::AnimatedRows>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl AnimatedRows {
    pub fn new(
        child: &impl IsA<gtk::Widget>,
        containers: &[gtk::Widget],
        row_key: RowKeyFn,
    ) -> Self {
        let obj: Self = glib::Object::new();
        let imp = obj.imp();
        imp.progress.set(1.0);
        imp.child.set(child.clone().upcast()).unwrap();
        imp.containers.set(containers.to_vec()).unwrap();
        imp.row_key.set(row_key).ok();
        child.set_parent(&obj);

        let target = adw::CallbackAnimationTarget::new(glib::clone!(
            #[weak]
            obj,
            move |value| {
                obj.imp().progress.set(value);
                obj.queue_allocate();
            }
        ));
        let animation = adw::TimedAnimation::new(&obj, 0.0, 1.0, 300, target);
        animation.set_easing(adw::Easing::EaseOutCubic);
        animation.connect_done(glib::clone!(
            #[weak]
            obj,
            move |_| {
                obj.imp().offsets.borrow_mut().clear();
                obj.queue_allocate();
            }
        ));
        imp.animation.set(animation).unwrap();
        obj
    }

    // Call before the rows are rebuilt
    pub fn begin_reorder(&self) {
        let imp = self.imp();
        // Several rebuilds can happen before the next allocation. Keep the
        // last visible positions.
        if imp.reorder_pending.get() {
            return;
        }

        imp.previous_positions.borrow_mut().clear();
        if self.is_mapped() && adw::is_animations_enabled(self) {
            let child = imp.child.get().unwrap();
            for row in imp.tracked_rows() {
                let Some(key) = (imp.row_key.get().unwrap())(&row) else {
                    continue;
                };
                let Some(bounds) = row.compute_bounds(child) else {
                    continue;
                };
                imp.previous_positions
                    .borrow_mut()
                    .insert(key, (bounds.x(), bounds.y()));
            }
        }

        imp.animation.get().unwrap().reset();
        imp.offsets.borrow_mut().clear();
        imp.reorder_pending
            .set(!imp.previous_positions.borrow().is_empty());
    }
}
