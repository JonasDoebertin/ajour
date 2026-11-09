# dmgbuild settings for Ajour's disk image. scripts/build-dmg.sh passes the app and the background as defines.
import os.path

application = defines["app"]  # noqa: F821, provided by dmgbuild
application_name = os.path.basename(application)

format = "ULFO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

# dmgbuild finds background@2x.png next to it and combines both into one HiDPI image.
background = defines["background"]  # noqa: F821, provided by dmgbuild
# Finder's window bounds include the 32 pt title bar of macOS 26, so the content area matches the 640 × 400 background.
window_rect = ((200, 120), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False

icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    application_name: (160, 190),
    "Applications": (480, 190),
}
