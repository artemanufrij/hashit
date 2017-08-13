/*-
 * Copyright (c) 2017-2017 Artem Anufrij <artem.anufrij@live.de>
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
                    calculate.begin ();
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
            this.set_titlebar (headerbar);

            open_file = new Gtk.Button.from_icon_name ("document-open", Gtk.IconSize.LARGE_TOOLBAR);
            open_file.tooltip_text = _("Open a file");
            open_file.clicked.connect (() => {
                open_file_dialog ();
            });
            headerbar.pack_start (open_file);

            hash_chooser = new Gtk.ComboBoxText ();
            hash_chooser.append ("md5sum", "MD5");
            hash_chooser.append ("sha256sum", "SHA256");
            hash_chooser.append ("sha1sum", "SHA1");
            hash_chooser.active = 1;
            hash_chooser.tooltip_text = _("Choose an algorithm");
            hash_chooser.changed.connect (() => {
                calculate.begin ();
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

            hash_result = new Gtk.Label (("<i>%s</i>").printf(_("Choose a file…")));
            hash_result.use_markup = true;
            hash_result.xalign = 0.5f;

            content.attach (reference_hash, 0, 1);
            content.attach (hash_result, 0, 0);

            this.add (content);
            this.show_all ();
            open_file.grab_focus ();
        }

        private void check_equal () {
            string reference = reference_hash.text;
            string result = hash_result.label;

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

            if (file.run () == Gtk.ResponseType.ACCEPT) {
                selected_file = file.get_file ();
                debug (file.get_filename ());
            }

            file.destroy();
        }

        private async void calculate () {
            calculate_begin ();
            string hash = hash_chooser.active_id;
            string path = selected_file.get_path ();
            debug (hash);
            debug (path);

            try {
                string[] spawn_args = {hash, path};
                Pid child_pid;
                int standard_output;

                Process.spawn_async_with_pipes ("/", spawn_args, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                null, out child_pid, null, out standard_output, null);

                // stdout:
                IOChannel output = new IOChannel.unix_new (standard_output);
                output.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                    return process_line (channel, condition);
                });

                ChildWatch.add (child_pid, (pid, status) => {
                    Process.close_pid (pid);
                });
            } catch (SpawnError e) {
                stdout.printf ("Error: %s\n", e.message);
            }
        }

        private bool process_line (IOChannel channel, IOCondition condition) {
	        if (condition == IOCondition.HUP) {
		        return false;
	        }

	        try {
		        string line = "";
		        channel.read_line (out line, null, null);

                GLib.Regex re = new GLib.Regex ("^(\\w)*");
                MatchInfo mi;
                string result = "";
                if (re.match (line, 0 , out mi)) {
                    result = mi.fetch (0);
                    debug (result);
                }
                calculate_finished (result);
            } catch (GLib.RegexError e) {
                warning ("RegexError: %s\n", e.message);
                calculate_finished ("");
	        } catch (IOChannelError e) {
		        warning ("IOChannelError: %s\n", e.message);
		        return false;
	        } catch (ConvertError e) {
		        warning ("ConvertError: %s\n", e.message);
		        return false;
	        }

	        return true;
        }
    }
}
