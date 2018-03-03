/*-
 * Copyright (c) 2017-2018 Artem Anufrij <artem.anufrij@live.de>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The Noise authors hereby grant permission for non-GPL compatible
 * GStreamer plugins to be used and distributed together with GStreamer
 * and Noise. This permission is above and beyond the permissions granted
 * by the GPL license by which Noise is covered. If you modify this code
 * you may extend this exception to your version of the code, but you are not
 * obligated to do so. If you do not wish to do so, delete this exception
 * statement from your version.
 *
 * Authored by: Artem Anufrij <artem.anufrij@live.de>
 */

namespace HashIt {

    public class MainWindow : Gtk.Window {

        public signal void calculate_begin ();
        public signal void calculate_finished (string result);

        Gtk.Grid content;
        Gtk.Label hash_result;
        Gtk.Button open_file;
        Gtk.ComboBoxText hash_chooser;
        Gtk.Entry reference_hash;
        Gtk.Spinner hash_waiting;
        Gtk.HeaderBar headerbar;
        Gtk.Menu menu;

        private const Gtk.TargetEntry[] targets = {
            {"text/uri-list",0,0}
        };

        File _selected_file = null;
        public File selected_file {
            get {
                return _selected_file;
            }
            set {
                _selected_file = value;
                hash_result.label = "";

                if (selected_file != null) {
                    this.set_file_path_label (selected_file.get_basename ());
                    get_checksum.begin ();
                } else {
                    this.set_file_path_label ("");
                }
            }
        }

        public MainWindow () {
            this.resizable = false;
            this.width_request = 660;

            build_ui ();

            calculate_begin.connect (() => {
                hash_waiting.active = true;
                hash_chooser.sensitive = false;
                open_file.sensitive = false;
                hash_result.label = ("<i>%s</i>").printf(_("Calculating checksum…"));
            });

            calculate_finished.connect ((result) => {
                hash_result.label = result;
                hash_waiting.active = false;
                hash_chooser.sensitive = true;
                open_file.sensitive = true;
                check_equal ();
            });

            Gtk.drag_dest_set (this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.LINK);

            drag_motion.connect ((context, x, y, time) => {
                Gtk.drag_unhighlight (this);
                return true;
            });
            drag_data_received.connect ((drag_context, x, y, data, info, time) => {
                if (data.get_uris ().length > 0) {
                    selected_file = File.new_for_uri (data.get_uris () [0]);
                }
            });

            present ();
        }

        private void build_ui () {
            content = new Gtk.Grid ();
            content.margin = 12;
            content.row_spacing = 12;
            content.column_homogeneous = true;

            headerbar = new Gtk.HeaderBar ();
            headerbar.show_close_button = true;
            headerbar.title = _("Hash It");
            headerbar.get_style_context ().add_class("flat");
            this.set_titlebar (headerbar);

            open_file = new Gtk.Button.from_icon_name ("document-open", Gtk.IconSize.LARGE_TOOLBAR);
            open_file.tooltip_text = _("Open a file");
            open_file.clicked.connect (() => {
                open_file_dialog ();
            });
            headerbar.pack_start (open_file);

            hash_chooser = new Gtk.ComboBoxText ();
            hash_chooser.append ("MD5", "MD5");
            hash_chooser.append ("SHA256", "SHA256");
            hash_chooser.append ("SHA1", "SHA1");
            hash_chooser.active = 1;
            hash_chooser.tooltip_text = _("Choose an algorithm");
            hash_chooser.changed.connect (() => {
                if (selected_file != null) {
                    get_checksum.begin ();
                }
            });
            headerbar.pack_end (hash_chooser);

            hash_waiting = new Gtk.Spinner ();
            headerbar.pack_end (hash_waiting);

            reference_hash = new Gtk.Entry ();
            reference_hash.xalign = 0.5f;
            reference_hash.placeholder_text = _("(optional) paste a reference hash here…");
            reference_hash.changed.connect (() => {
                 check_equal ();
            });

            hash_result = new Gtk.Label (("<i>%s</i>").printf(_("Choose a file or drag one onto this window…")));
            hash_result.use_markup = true;
            hash_result.xalign = 0.5f;

            var event_box = new Gtk.EventBox ();
            event_box.button_press_event.connect (show_context_menu);
            event_box.add (hash_result);

            menu = new Gtk.Menu ();
            var menu_copy = new Gtk.MenuItem.with_label (_("Copy result…"));
            menu_copy.activate.connect (() => {
                Gtk.Clipboard.get_default (Gdk.Display.get_default ()).set_text (this.hash_result.label, -1);
            });

            menu.append (menu_copy);
            menu.show_all ();

            content.attach (reference_hash, 0, 1);
            content.attach (event_box, 0, 0);

            this.add (content);
            this.show_all ();
            open_file.grab_focus ();
        }

        private bool show_context_menu (Gtk.Widget sender, Gdk.EventButton evt) {
            if (evt.button == 1 && open_file.sensitive) {
                open_file_dialog ();
                return true;
            } else if (evt.type == Gdk.EventType.BUTTON_PRESS && evt.button == 3 && selected_file != null && !hash_waiting.active) {
                menu.popup (null, null, null, evt.button, evt.time);
                return true;
            }
            return false;
        }

        private void check_equal () {
            string reference = reference_hash.text.down ();
            string result = hash_result.label.down ();

            reference_hash.set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, null);

            if (reference != "" && result != "") {
                if (reference != result) {
                    reference_hash.set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, "process-error");
                } else {
                    reference_hash.set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, "process-completed");
                }
            }
        }

        private void set_file_path_label (string text) {
            headerbar.title = text;
        }

        private void open_file_dialog () {
            var file = new Gtk.FileChooserDialog (
                _("Open"), this,
                Gtk.FileChooserAction.OPEN,
                _("_Cancel"), Gtk.ResponseType.CANCEL,
                _("_Open"), Gtk.ResponseType.ACCEPT);

            var filter = new Gtk.FileFilter ();
            filter.set_filter_name (_("All files"));
            filter.add_pattern ("*");
            file.add_filter (filter);

            if (file.run () == Gtk.ResponseType.ACCEPT) {
                selected_file = file.get_file ();
                debug (file.get_filename ());
            }

            file.destroy();
        }

        private async void get_checksum () {
            calculate_begin ();
            checksum_thread.begin ((obj, res) => {
                calculate_finished (checksum_thread.end (res));
            });
        }

        private async string checksum_thread () {
            SourceFunc callback = checksum_thread.callback;
            ChecksumType checksumtype = ChecksumType.SHA256;
            switch (hash_chooser.active_id) {
                case "MD5":
                    checksumtype = ChecksumType.MD5;
                    break;
                case "SHA1":
                    checksumtype = ChecksumType.SHA1;
                    break;
                case "SHA256":
                    checksumtype = ChecksumType.SHA256;
                    break;
                case "SHA512":
                    checksumtype = ChecksumType.SHA512;
                    break;
            }
            string digest = "";

            ThreadFunc<void*> run = () => {
                Checksum checksum = new Checksum (checksumtype);
                FileStream stream = FileStream.open (selected_file.get_path (), "r");
                uint8 fbuf[100];
                size_t size;

                while ((size = stream.read (fbuf)) > 0) {
                    checksum.update (fbuf, size);
                }
                digest = checksum.get_string ();
                Idle.add ((owned) callback);
                return null;
            };
            try {
                new Thread<void*>.try (null, run);
            } catch (Error e) {
                warning (e.message);
            }

            yield;
            return digest;
        }
    }
}
