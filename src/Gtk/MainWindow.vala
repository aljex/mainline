/*
 * MainWindow.vala
 *
 * Copyright 2012 Tony George <teejee2008@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using Gtk;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

public class MainWindow : Gtk.Window{

    private Gtk.HeaderBar hbar;
	private Gtk.Box vbox_main;
	private Gtk.Box hbox_list;

	private Gtk.TreeView tv;
	private Gtk.Button btn_refresh;
	private Gtk.Button btn_install;
	private Gtk.Button btn_remove;
	private Gtk.Button btn_purge;
	private Gtk.Button btn_changes;
	private Gtk.Label lbl_info;

	// helper members

	private int window_width = 800;
	private int window_height = 600;
	private uint tmr_init = -1;

	private Gee.ArrayList<LinuxKernel> selected_kernels;

	public MainWindow() {

		title = BRANDING_LONGNAME;
		window_position = WindowPosition.CENTER;
		icon = get_app_icon(16);

        // hbar
        hbar = new Gtk.HeaderBar();
        hbar.set_show_close_button(true);
        set_titlebar(hbar);

		// vbox_main
		vbox_main = new Gtk.Box(Orientation.VERTICAL, 6);
		vbox_main.margin = 6;
		vbox_main.set_size_request(window_width, window_height);
		add (vbox_main);

		selected_kernels = new Gee.ArrayList<LinuxKernel>();

		init_ui();

		tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {

		/* any actions that need to run after window has been displayed */

		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		refresh_cache();

		tv_refresh();

		switch (App.command){
		case "install":

			LinuxKernel kern_requested = null;
			foreach(var kern in LinuxKernel.kernel_list){
				if (kern.version_main == App.requested_version){
					kern_requested = kern;
					break;
				}
			}

			if (kern_requested == null){
				var msg = _("Could not find requested version");
				msg += ": %s".printf(App.requested_version);
				log_error(msg);
				exit(1);
			}
			else{
				install(kern_requested);
			}

			break;

		}

		return false;
	}

	private void init_ui(){
		init_treeview();
		init_actions();
		init_infobar();
	}

	private void init_treeview(){

		// hbox
		hbox_list = new Gtk.Box(Orientation.HORIZONTAL, 6);
		//hbox.margin = 6;
		vbox_main.add(hbox_list);

		//add treeview
		tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.headers_visible = true;
		tv.expand = true;

		tv.row_activated.connect(tv_row_activated);

		tv.get_selection().changed.connect(tv_selection_changed);

		var scrollwin = new ScrolledWindow(tv.get_hadjustment(), tv.get_vadjustment());
		scrollwin.set_shadow_type (ShadowType.ETCHED_IN);
		scrollwin.add (tv);
		hbox_list.add(scrollwin);

		//column
		var col = new TreeViewColumn();
		col.title = _("Kernel");
		col.resizable = true;
		col.min_width = 200;
		tv.append_column(col);

		// cell icon
		var cell_pix = new Gtk.CellRendererPixbuf ();
		cell_pix.xpad = 4;
		cell_pix.ypad = 6;
		col.pack_start (cell_pix, false);
		col.set_cell_data_func (cell_pix, (cell_layout, cell, model, iter)=>{
			Gdk.Pixbuf pix;
			model.get (iter, 1, out pix, -1);
			(cell as Gtk.CellRendererPixbuf).pixbuf = pix;
		});

		//cell text
		var cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			LinuxKernel kern;
			model.get (iter, 0, out kern, -1);
			(cell as Gtk.CellRendererText).text = kern.version_main;
		});

		//column
		col = new TreeViewColumn();
		col.title = _("Status");
		col.resizable = true;
		col.min_width = 200;
		tv.append_column(col);

		//cell text
		cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			LinuxKernel kern;
			model.get (iter, 0, out kern, -1);
			(cell as Gtk.CellRendererText).text = kern.is_running ? _("Running") : (kern.is_installed ? _("Installed") : "");
		});

		//column
		col = new TreeViewColumn();
		col.title = "";
		tv.append_column(col);

		//cell text
		cellText = new CellRendererText();
		cellText.width = 10;
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);

		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			bool odd_row;
			model.get (iter, 2, out odd_row, -1);
		});

		tv.set_tooltip_column(3);
	}

	private void tv_row_activated(TreePath path, TreeViewColumn column){
		TreeIter iter;
		tv.model.get_iter_from_string(out iter, path.to_string());
		LinuxKernel kern;
		tv.model.get (iter, 0, out kern, -1);

		set_button_state();
	}

	private void tv_selection_changed(){
		var sel = tv.get_selection();

		TreeModel model;
		TreeIter iter;
		var paths = sel.get_selected_rows (out model);

		selected_kernels.clear();
		foreach(var path in paths){
			LinuxKernel kern;
			model.get_iter(out iter, path);
			model.get (iter, 0, out kern, -1);
			selected_kernels.add(kern);
			//log_msg("size=%d".printf(selected_kernels.size));
		}

		set_button_state();
	}

	private void tv_refresh(){
		log_debug("tv_refresh()");
		var model = new Gtk.ListStore(4, typeof(LinuxKernel), typeof(Gdk.Pixbuf), typeof(bool), typeof(string));

		Gdk.Pixbuf pix_ubuntu = null;
		Gdk.Pixbuf pix_mainline = null;
		Gdk.Pixbuf pix_mainline_rc = null;

		try {
			pix_ubuntu = new Gdk.Pixbuf.from_file (INSTALL_PREFIX + "/share/pixmaps/" + BRANDING_SHORTNAME + "/ubuntu-logo.png");
			pix_mainline = new Gdk.Pixbuf.from_file (INSTALL_PREFIX + "/share/pixmaps/" + BRANDING_SHORTNAME + "/tux.png");
			pix_mainline_rc = new Gdk.Pixbuf.from_file (INSTALL_PREFIX + "/share/pixmaps/" + BRANDING_SHORTNAME + "/tux-red.png");
		}
		catch (Error e) {
			log_error (e.message);
		}

		TreeIter iter;
		bool odd_row = false;
		foreach(var kern in LinuxKernel.kernel_list) {
			if (!kern.is_valid) continue;
			if (!kern.is_installed) {
				if (App.hide_unstable && kern.is_unstable) continue;
				if (kern.version_maj < LinuxKernel.highest_maj-App.show_prev_majors) continue;
			}

			odd_row = !odd_row;

			//add row
			model.append(out iter);
			model.set (iter, 0, kern);

			if (kern.is_mainline){
				if (kern.is_unstable){
					model.set (iter, 1, pix_mainline_rc);
				}
				else{
					model.set (iter, 1, pix_mainline);
				}
			}
			else{
				model.set (iter, 1, pix_ubuntu);
			}

			model.set (iter, 2, odd_row);
			model.set (iter, 3, kern.tooltip_text());
		}

		tv.set_model(model);
		tv.columns_autosize();

		selected_kernels.clear();
		set_button_state();

		set_infobar();
	}

	private void set_button_state(){
		if (selected_kernels.size == 0){
			btn_install.sensitive = false;
			btn_remove.sensitive = false;
			btn_purge.sensitive = true;
			btn_changes.sensitive = false;
		}
		else{
			btn_install.sensitive = (selected_kernels.size == 1) && !selected_kernels[0].is_installed;
			btn_remove.sensitive = selected_kernels[0].is_installed && !selected_kernels[0].is_running;
			btn_purge.sensitive = true;
			btn_changes.sensitive = (selected_kernels.size == 1) && file_exists(selected_kernels[0].changes_file);
		}
	}

	private void init_actions(){
        // menu
        var menu_button = new Gtk.Button.from_icon_name ("open-menu-symbolic");
        var pop = new Gtk.Popover (menu_button);
        var pop_hbox = new Gtk.Box(Orientation.VERTICAL, 6);
        pop.add(pop_hbox);
        menu_button.clicked.connect (() => {
            pop.show_all();
        });
        hbar.pack_end(menu_button);

		// refresh
		var button = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
		button.set_tooltip_text(_("Refresh"));
		hbar.pack_start (button);
		btn_refresh = button;

		button.clicked.connect(() => {

			if (!check_internet_connectivity()){
				gtk_messagebox(_("No Internet"), _("Internet connection is not active"), this, true);
				return;
			}

			refresh_cache();
			tv_refresh();
		});

		// install
		button = new Gtk.Button.from_icon_name ("list-add-symbolic");
		button.set_tooltip_text(_("Install"));
		hbar.pack_start (button);
		btn_install = button;

		button.clicked.connect(() => {
			if (selected_kernels.size == 1){
				install(selected_kernels[0]);
			}
			else if (selected_kernels.size > 1){
				gtk_messagebox(_("Multiple Kernels Selected"),_("Select a single kernel to install"), this, true);
			}
			else{
				gtk_messagebox(_("Not Selected"),_("Select the kernel to install"), this, true);
			}
		});

		// changes
		button = new Gtk.Button.from_icon_name ("view-layout-symbolic");
		button.set_tooltip_text(_("Changes"));
		hbar.pack_start (button);
		btn_changes = button;

		button.clicked.connect(() => {
			if ((selected_kernels.size == 1) && file_exists(selected_kernels[0].changes_file)){
				xdg_open(selected_kernels[0].changes_file);
			}
		});

		// remove
		button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
		button.set_tooltip_text(_("Remove"));
		hbar.pack_start (button);
		btn_remove = button;

		button.clicked.connect(() => {
			if (selected_kernels.size == 0){
				gtk_messagebox(_("Not Selected"),_("Select the kernels to remove"), this, true);
			}
			else if (selected_kernels.size > 0){
				
				var term = new TerminalWindow.with_parent(this, false, true);
				string t_dir = create_tmp_dir();
				string t_file = get_temp_file_path(t_dir)+".sh";

				term.script_complete.connect(()=>{
					term.allow_window_close();
					file_delete(t_file);
					dir_delete(t_dir);
				});

				term.destroy.connect(()=>{
					this.present();
					refresh_cache();
					tv_refresh();
				});

				string names = "";
				foreach(var kern in selected_kernels){
					if (names.length > 0) names += ",";
					names += "%s".printf(kern.version_main);
				}

				string sh = BRANDING_SHORTNAME;
				if (LOG_DEBUG) sh += " --debug";
				sh += " --remove %s\n".printf(names)
				+ "echo \n"
				+ "echo '"+_("Close window to exit...")+"'\n";

				save_bash_script_temp(sh,t_file);
				term.execute_script(t_file,t_dir);
			}
		});

		// purge
		var model_button = new Gtk.ModelButton ();
		model_button.text = ("Purge");
		model_button.set_tooltip_text(_("Remove installed kernels older than running kernel"));
		pop_hbox.add (model_button);
		btn_purge = button;

		button.clicked.connect(() => {

			var term = new TerminalWindow.with_parent(this, false, true);
			string t_dir = create_tmp_dir();
			string t_file = get_temp_file_path(t_dir)+".sh";

			term.script_complete.connect(()=>{
				term.allow_window_close();
				file_delete(t_file);
				dir_delete(t_dir);
			});

			term.destroy.connect(()=>{
				this.present();
				refresh_cache();
				tv_refresh();
			});

			string sh = BRANDING_SHORTNAME+" --purge-old-kernels";
			if (LOG_DEBUG) sh += " --debug";
			sh += "\necho \n"
			+ "echo '"+_("Close window to exit...")+"'\n";

			save_bash_script_temp(sh,t_file);
			term.execute_script(t_file,t_dir);
		});

		// settings
		model_button = new Gtk.ModelButton ();
		model_button.text = ("Settings");
		model_button.set_tooltip_text(("Settings"));
		pop_hbox.add (model_button);

		model_button.clicked.connect(() => {

			int _show_prev_majors = App.show_prev_majors;
			bool _hide_unstable = App.hide_unstable;

			var dlg = new SettingsDialog.with_parent(this);
			dlg.run();
			dlg.destroy();

			if (
				(_show_prev_majors != App.show_prev_majors)
				|| (_hide_unstable != App.hide_unstable)
			   ) {
				refresh_cache();
			}

			tv_refresh();
		});

		// about
		model_button = new Gtk.ModelButton ();
		model_button.text = ("About");
		model_button.set_tooltip_text(("About"));
		pop_hbox.add (model_button);

		model_button.clicked.connect(btn_about_clicked);
	}

	private void btn_about_clicked () {

		var dialog = new AboutWindow();
		dialog.set_transient_for (this);

		// FIXME - this should come from the AUTHORS file, or from git
		dialog.authors = {
			"Tony George <teejeetech@gmail.com>",
			BRANDING_AUTHORNAME+" <"+BRANDING_AUTHOREMAIL+">"
		};

		// FIXME - generate this list from the .po files
		/*
		dialog.translators = {
			"name",
			"name",
			"name"
		};
		*/
		// For now, run "make TRANSLATORS"
		// then cut & paste from generated TRANSLATORS file
		// and add the quotes & commas
		dialog.translators = {
			"es: Adolfo Jayme Barrientos <fitojb@ubuntu.com>",
			"fr: Yolateng0 <yo@yo.nohost.me>",
			"hr: gogo <trebelnik2@gmail.com>",
			"it: Albano Battistella <albano_battistella@hotmail.com>",
			"nl: Heimen Stoffels <vistausss@outlook.com>",
			"pl: Waldemar Konik <valdi74@github>",
			"ru: Faust3000 <slavusik1988@gmail.com>",
			"sv: Åke Engelbrektson <eson@svenskasprakfiler.se>",
			"tr: Gökhan GÖKKAYA <gokhanlnx@gmail.com>",
			"uk: Serhii Golovko <cappelikan@gmail.com>",
		};

		dialog.documenters = null;
		dialog.artists = null;

		dialog.program_name = BRANDING_LONGNAME;
		dialog.comments = _("Kernel upgrade utility for Ubuntu-based distributions");
		dialog.copyright = _("Original")+": \"ukuu\" © 2015-18 Tony George\n"+_("Forked")+": \""+BRANDING_SHORTNAME+"\" 2019 "+BRANDING_AUTHORNAME+" ("+BRANDING_AUTHOREMAIL+")";
		dialog.version = BRANDING_VERSION;
		dialog.logo = get_app_icon(128);

		dialog.license = "This program is free for personal and commercial use and comes with absolutely no warranty. You use this program entirely at your own risk. The author will not be liable for any damages arising from the use of this program.";
		dialog.website = BRANDING_WEBSITE;
		dialog.website_label = BRANDING_WEBSITE;

		dialog.third_party = {
			"Elementary project (various icons):github.com/elementary/icons",
			"Tango project (various icons):tango.freedesktop.org/Tango_Desktop_Project",
			"notify-send.sh:github.com/vlevit/notify-send.sh"
		};

		dialog.initialize();
		dialog.show_all();
	}

	private void refresh_cache(bool download_index = true){

		if (!check_internet_connectivity()){
			gtk_messagebox(_("No Internet"), _("Internet connection is not active."), this, true);
			return;
		}

		if (App.command != "list"){

			// refresh without GUI and return -----------------

			LinuxKernel.query(false);

			while (LinuxKernel.task_is_running) {

				sleep(200);
				gtk_do_events();
			}

			return;
		}

		string message = _("Refreshing...");
		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();

		// TODO: Check if kernel.ubuntu.com is down

		LinuxKernel.query(false);

		var timer = timer_start();

		App.progress_total = 1;
		App.progress_count = 0;

		string msg_remaining = "";
		long count = 0;

		while (LinuxKernel.task_is_running) {

			if (App.cancelled){
				App.exit_app(1);
			}

			App.status_line = LinuxKernel.status_line;
			App.progress_total = LinuxKernel.progress_total;
			App.progress_count = LinuxKernel.progress_count;

			ulong ms_elapsed = timer_elapsed(timer, false);
			int64 remaining_count = App.progress_total - App.progress_count;
			int64 ms_remaining = (int64)((ms_elapsed * 1.0) / App.progress_count) * remaining_count;

			if ((count % 5) == 0){
				msg_remaining = format_time_left(ms_remaining);
			}

			if (App.progress_total > 0){
				dlg.update_message("%s %s/%s (%s)".printf(message, App.progress_count.to_string(), App.progress_total.to_string(), msg_remaining));
			}

			dlg.update_status_line();

			// FIXME - GTK error messages, and progressbar is always 100%
			//dlg.update_progressbar();

			gtk_do_events();

			dlg.sleep(200);

			count++;
		}

		timer_elapsed(timer, true);

		dlg.destroy();
		gtk_do_events();
	}


	private void init_infobar(){

		// scrolled
		var scrolled = new ScrolledWindow(null, null);
		scrolled.set_shadow_type (ShadowType.ETCHED_IN);
		//scrolled.margin = 6;
		scrolled.margin_top = 0;
		scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
		scrolled.vscrollbar_policy = Gtk.PolicyType.NEVER;
		vbox_main.add(scrolled);

		// hbox
		var hbox = new Gtk.Box(Orientation.HORIZONTAL, 6);
		//hbox.margin = 6;
		scrolled.add(hbox);

		lbl_info = new Gtk.Label("");
		lbl_info.margin = 6;
		lbl_info.set_use_markup(true);
		hbox.add(lbl_info);
	}

	private void set_infobar(){

		if (LinuxKernel.kernel_active != null){

			lbl_info.label = _("Running")+" <b>%s</b>".printf(LinuxKernel.kernel_active.version_main);

			if (LinuxKernel.kernel_active.is_mainline){
				lbl_info.label += " (mainline)";
			}
			else{
				lbl_info.label += " (ubuntu)";
			}

			if (LinuxKernel.kernel_latest_available.compare_to(LinuxKernel.kernel_latest_installed) > 0){
				lbl_info.label += " ~ <b>%s</b> ".printf(LinuxKernel.kernel_latest_available.version_main)+_("available");
			}
		}
		else{
			lbl_info.label = _("Running")+" <b>%s</b>".printf(LinuxKernel.RUNNING_KERNEL);
		}
	}

	public void install(LinuxKernel kern){

		// check if installed
		if (kern.is_installed){
			gtk_messagebox(_("Already Installed"), _("This kernel is already installed."), this, true);
			return;
		}

		if (!check_internet_connectivity()){
			gtk_messagebox(_("No Internet"), _("Internet connection is not active."), this, true);
			return;
		}

		var term = new TerminalWindow.with_parent(this, false, true);
		string t_dir = create_tmp_dir();
		string t_file = get_temp_file_path(t_dir)+".sh";

		term.script_complete.connect(()=>{
			term.allow_window_close();
			file_delete(t_file);
			dir_delete(t_dir);
		});

		term.destroy.connect(()=>{

			if (App.command == "list"){
				this.present();
				refresh_cache();
				tv_refresh();
			}
			else{
				this.destroy();
				Gtk.main_quit();
				App.exit_app(0);
			}
		});

		string sh = BRANDING_SHORTNAME;
		if (LOG_DEBUG) sh += " --debug";
		sh += " --install %s\n".printf(kern.version_main)
		+ "echo \n"
		+ "echo '"+_("Close window to exit...")+"'\n";

		save_bash_script_temp(sh,t_file);
		term.execute_script(t_file,t_dir);
	}

}
