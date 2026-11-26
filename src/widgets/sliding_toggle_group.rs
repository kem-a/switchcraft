// Adw.ToggleGroup whose selection slides between toggles. Draws the group
// background and a checked toggle below the real Adw.ToggleGroup, which
// style.css makes transparent. Both use the toggle-group CSS names, so they
// follow the libadwaita theme.

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::glib;
use gtk::{graphene, gsk};
use std::cell::{OnceCell, RefCell};

use crate::i18n::gettext;

mod indicator_imp {
    use super::*;

    #[derive(Default)]
    pub struct Indicator;

    #[glib::object_subclass]
    impl ObjectSubclass for Indicator {
        const NAME: &'static str = "SwitchcraftSlidingToggleGroupIndicator";
        type Type = super::Indicator;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("toggle");
        }
    }

    impl ObjectImpl for Indicator {
        fn constructed(&self) {
            self.parent_constructed();
            let obj = self.obj();
            obj.set_can_target(false);
            obj.set_state_flags(gtk::StateFlags::CHECKED, false);
        }
    }

    impl WidgetImpl for Indicator {}
}

glib::wrapper! {
    pub struct Indicator(ObjectSubclass<indicator_imp::Indicator>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct SlidingToggleGroup {
        pub group: OnceCell<adw::ToggleGroup>,
        pub indicator: RefCell<Option<Indicator>>,
        pub animation: OnceCell<adw::TimedAnimation>,
        pub from_rect: RefCell<graphene::Rect>,
        pub current_rect: RefCell<graphene::Rect>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for SlidingToggleGroup {
        const NAME: &'static str = "SwitchcraftSlidingToggleGroup";
        type Type = super::SlidingToggleGroup;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("toggle-group");
        }
    }

    impl ObjectImpl for SlidingToggleGroup {
        fn dispose(&self) {
            if let Some(indicator) = self.indicator.take() {
                indicator.unparent();
            }
            if let Some(group) = self.group.get() {
                group.unparent();
            }
        }
    }

    impl WidgetImpl for SlidingToggleGroup {
        fn request_mode(&self) -> gtk::SizeRequestMode {
            self.group().request_mode()
        }

        fn measure(&self, orientation: gtk::Orientation, for_size: i32) -> (i32, i32, i32, i32) {
            self.group().measure(orientation, for_size)
        }

        fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
            self.group().allocate(width, height, baseline, None);

            let Some(indicator) = self.indicator.borrow().clone() else {
                return;
            };
            let target = self
                .active_toggle()
                .and_then(|toggle| toggle.compute_bounds(&*self.obj()));
            let Some(target) = target else {
                indicator.set_child_visible(false);
                return;
            };
            indicator.set_child_visible(true);

            let animation = self.animation.get().unwrap();
            let current = if animation.state() == adw::AnimationState::Playing {
                self.from_rect
                    .borrow()
                    .interpolate(&target, animation.value())
            } else {
                target
            };
            *self.current_rect.borrow_mut() = current;

            let transform =
                gsk::Transform::new().translate(&graphene::Point::new(current.x(), current.y()));
            indicator.allocate(
                (current.width() + 0.5) as i32,
                (current.height() + 0.5) as i32,
                -1,
                Some(transform),
            );
        }
    }

    impl SlidingToggleGroup {
        fn group(&self) -> &adw::ToggleGroup {
            self.group.get().unwrap()
        }

        fn active_toggle(&self) -> Option<gtk::Widget> {
            let active = self.group().active();
            let mut index = 0;
            let mut child = self.group().first_child();
            while let Some(widget) = child {
                // Toggles alternate with separators
                if !widget.is::<gtk::Separator>() {
                    if index == active {
                        return Some(widget);
                    }
                    index += 1;
                }
                child = widget.next_sibling();
            }
            None
        }
    }
}

glib::wrapper! {
    pub struct SlidingToggleGroup(ObjectSubclass<imp::SlidingToggleGroup>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl SlidingToggleGroup {
    // The light/dark toggle used by command rows and the command dialog
    pub fn for_theme(theme: &str) -> Self {
        let group = adw::ToggleGroup::new();
        group.add(
            adw::Toggle::builder()
                .name("light")
                .icon_name("weather-clear-symbolic")
                .tooltip(gettext("Light"))
                .build(),
        );
        group.add(
            adw::Toggle::builder()
                .name("dark")
                .icon_name("weather-clear-night-symbolic")
                .tooltip(gettext("Dark"))
                .build(),
        );
        group.set_active_name(Some(theme));
        let toggle = SlidingToggleGroup::new(&group);
        toggle.set_valign(gtk::Align::Center);
        toggle
    }

    pub fn new(group: &adw::ToggleGroup) -> Self {
        let obj: Self = glib::Object::new();
        let imp = obj.imp();
        imp.group.set(group.clone()).unwrap();
        obj.add_css_class("round");
        obj.add_css_class("sliding");
        group.add_css_class("round");

        let indicator: Indicator = glib::Object::new();
        indicator.set_parent(&obj);
        imp.indicator.replace(Some(indicator));
        group.set_parent(&obj);

        let target = adw::CallbackAnimationTarget::new(glib::clone!(
            #[weak]
            obj,
            move |_| obj.queue_allocate()
        ));
        let animation = adw::TimedAnimation::new(&obj, 0.0, 1.0, 250, target);
        animation.set_easing(adw::Easing::EaseOutCubic);
        imp.animation.set(animation).unwrap();

        group.connect_active_notify(glib::clone!(
            #[weak]
            obj,
            move |_| {
                let imp = obj.imp();
                let current = *imp.current_rect.borrow();
                *imp.from_rect.borrow_mut() = current;
                imp.animation.get().unwrap().play();
            }
        ));
        obj
    }

    pub fn group(&self) -> adw::ToggleGroup {
        self.imp().group.get().unwrap().clone()
    }
}
