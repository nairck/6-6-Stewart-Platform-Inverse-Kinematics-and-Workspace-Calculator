# MATLAB version

The original MATLAB implementation of the Hexapod IK & Workspace Calculator. This is
the reference version; the [Python port](../python/) and the Windows executable reproduce its math,
file formats, and workflow.

For the full description of what the tool does (geometry, IK, workspace analysis, screenshots), see
the [main README](../README.md).

## Requirements

- MATLAB **R2020b or later**, with GUI support
- 64-bit Windows (tested on Windows 11)
- The workspace sweeps call the plain `stew_inverse_ws.m`. The `codegen/` folder and
  `stew_inverse_ws_mex.mexw64` were generated for the earlier plane-height signature and are not
  used; regenerate them with the `codegen` line at the top of `stew_inverse_ws.m` if you want a MEX
  build of the current per-joint-Z solver.

## Run

1. Open MATLAB.
2. Set the working directory to this `matlab/` folder and add it (and subfolders) to the path.
3. Run:

   ```matlab
   >> RUN_HEXAPOD_CALCULATOR
   ```

## File overview

- `RUN_HEXAPOD_CALCULATOR.m` — main entry point
- `MAIN_GUI.m` — GUI layout and logic
- `solve_inverse.m`, `stew_inverse.m`, `stew_inverse_ws.m` — IK and workspace solvers
- `draw_*.m`, `export_*.m`, `anim_plat.m` — visualization and export
- `edit_*.m`, `handle_*.m`, `*_data.m`, `*_callback.m` — dialogs, save/load, and button handlers
- `origin_dialog.m`, `apply_origin.m`, `refresh_origin_ui.m`, `origin_frame.m`,
  `frame_transition.m`, `change_frame.m` (`shift_frame.m` is its unrotated special case): origins /
  points of interest (the "Current Origin" button): modal list dialog, frame change with offset and
  orientation, button/lock refresh, pose re-expression maths
- `rotation_rpy.m`, `rpy_perm.m`, `rpy_from_rotation.m`, `convert_rpy_axes.m`, `apply_rpy_axes.m`,
  `refresh_angle_labels.m`, `rpy_axes_of.m`: the roll / pitch / yaw axes assignment (XYZ, YZX, ZXY)
- `incremental_adj_table.m`, `incremental_adj_rows.m`, `wrap_origin_name.m`, `adj_config_default.m`,
  `adj_config_normalise.m`, `adj_config_is_default.m`: the "Incremental Adj. Table" window, its maths,
  its text / Excel / PNG export and its saved set-up
- `export_sketch_axes.m`: the sketch drawn into an axes for the table exports
- `wrap_button_name.m`, `fit_button_font.m`: multi-line button labels (a MATLAB button shows only the
  first line of a cell-array label, so these are emitted as HTML) and their font sizing
- `last_save_dir.m`: the save folder remembered across the program's file dialogs
- `frame_view.m`, `dataset_view_frame.m`: the workspace windows viewed through the sketch's display
  frame stored with each dataset
- `change_coords_dialog.m`, `apply_axis_map.m`, `axis_map_matrix.m`, `axis_vector.m`,
  `axis_label.m`, `rpy_from_rotation.m`: the "Change Coords." right-handed axis relabelling
- `arrow_head.m`: solid 3D cone arrowhead used by the sketch and dialog triads
- `formdata_tags.m`, `state_signature.m`: the `formdata.txt` tag list / defaults shared by
  load and save, and the saved-state check behind Quit / Escape / the close button
- `stew_inverse_ws_mex.mexw64`, `codegen/` — stale compiled kernel for the previous solver signature (see Requirements)
- `formdata.txt` — platform/system configuration save file (auto-loaded on start)
- `*.mat` — example generated workspace data (reachable / orientation, NEW / RECALL)
