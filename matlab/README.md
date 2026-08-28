# MATLAB version

The original MATLAB implementation of the Hexapod IK & Workspace Calculator. It is the reference
version; the [Python port](../python/) and the Windows executable reproduce its maths, file formats
and workflow.

For what the tool does (geometry, inverse kinematics, origins, the incremental adjustment table,
workspace analysis, screenshots), see the [main README](../README.md).

Version 1.2, matching `hexapod_version.m`.

---

## Requirements

- MATLAB **R2020b or later**, with figure windows.
- 64-bit Windows is the tested platform. The program runs on macOS and Linux, with two limits: the
  Excel export needs Excel through COM (without it the workbook is written with the values only,
  and a console line says so), and the workspace `.mat` files are unaffected.
- The workspace sweeps call `stew_inverse_ws.m` directly. The `codegen/` folder and
  `stew_inverse_ws_mex.mexw64` were generated for the older plane-height signature and are not used;
  regenerate them with the `codegen` line at the top of `stew_inverse_ws.m` if you want a MEX build
  of the current per-joint-Z solver.

## Run

1. Open MATLAB.
2. Set the working folder to this `matlab/` folder and add it to the path.
3. Run:

   ```matlab
   >> RUN_HEXAPOD_CALCULATOR
   ```

## File overview

**Entry point and window**

- `RUN_HEXAPOD_CALCULATOR.m` — launcher
- `MAIN_GUI.m` — window layout and every button callback
- `hexapod_version.m` — the version string, matching the Python package

**Kinematics and geometry**

- `solve_inverse.m`, `stew_inverse.m`, `stew_inverse_ws.m` — inverse kinematics and the sweep solver
- `rotation_rpy.m`, `rpy_perm.m`, `rpy_from_rotation.m`, `convert_rpy_axes.m`, `apply_rpy_axes.m`,
  `rpy_axes_of.m`, `refresh_angle_labels.m` — roll, pitch and yaw about a chosen set of axes
- `origin_frame.m`, `frame_transition.m`, `change_frame.m`, `apply_origin.m`, `origin_dialog.m`,
  `refresh_origin_ui.m` — origins and points of interest
- `axis_vector.m`, `axis_label.m`, `axis_map_matrix.m`, `apply_axis_map.m`,
  `change_coords_dialog.m` — relabelling the coordinate axes

**Drawing and workspaces**

- `draw_plat.m`, `anim_plat.m`, `arrow_head.m`, `standard_display_frame.m` — the sketch
- `fit_sketch_view.m`, `reset_sketch_view.m`, `sketch_click_done.m` — centring and framing of the
  sketch; Reset View and a double-click do the same thing
- `draw_reachable_workspace_spherical.m`, `draw_orientation_workspace_spherical.m`,
  `export_reachable_workspace.m`, `export_orientation_workspace.m`, `frame_view.m`,
  `dataset_view_frame.m` — workspace sweeps, 3D windows and PNG export

**Incremental adjustment table**

- `incremental_adj_table.m` — the window and its text, PNG and Excel exports
- `incremental_adj_rows.m` — the per-leg turn ratios
- `export_sketch_axes.m`, `wrap_origin_name.m` — the origin previews and their labels
- `adj_config_default.m`, `adj_config_normalise.m`, `adj_config_is_default.m` — the saved set-up

**Files, settings and helpers**

- `load_data.m`, `save_data.m`, `formdata_tags.m`, `state_signature.m`, `home_data.m` — reading and
  writing `formdata.txt`, and the unsaved-changes check
- `last_save_dir.m` — the folder remembered across every file dialog
- `wrap_button_name.m`, `fit_button_font.m` — multi-line button labels
- `edit_zpd.m`, `edit_Constraints.m`, `applyAdjust.m`, `color_input_box.m`, `centerfig.m`, and the
  remaining `handle_*.m` callbacks — dialogs, field styling and button handlers

## Differences from the Python version

The maths, file formats, rounding and exports are identical. The interface differs only where
MATLAB's controls do:

- A table column that can be edited cannot carry formatting, so the Label and Turn columns are
  aligned with spaces rather than exactly; the read-only columns are aligned exactly.
- A table cannot merge cells, so an origin's name is written on the middle row of its group.
- The Excel export needs Excel itself for its pictures, colours and merged cells.
- The window has no docked console; messages go to the MATLAB command window.

## Credits

Original MATLAB tool by **Joe Brown** (CSU Sacramento, 2006), adapted and extended by
**Adam B. Johnson** (University of Victoria, 2022 to 2026).
