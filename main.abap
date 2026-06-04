*&---------------------------------------------------------------------*
*& Report Y_SCHEMA_EXPORT_GUS
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*

report y_schema_export_gus.

data:
  it_t52c1           type table of t52c1,
  it_t52c5           type table of t52c5,
  wa_t52c1           type t52c1,
  wa_t52c5           type t52c5,
  is_schem           type t52c1-schem,
  is_rule            type t52c5-ccycl,
  lt_result          type table of string,
  lt_schema_list     type table of t52c1-schem,
  lt_schema_list_aux type table of t52c1-schem,
  lt_rule_list       type table of t52c5-ccycl,
  gt_schema_list     type table of t52c1-schem,
  gt_rule_list       type table of t52c5-ccycl.
*  lt_new_schemas      type table of t52c1-schem.

selection-screen begin of block blck1.
  parameters:
    p_schem type t52c1-schem,
    p_path  type string.
selection-screen end of block blck1.

at selection-screen on value-request for p_path.

  call method cl_gui_frontend_services=>directory_browse
    changing
      selected_folder = p_path.

end-of-selection.

at selection-screen on p_schem.
  " Validate schema existance
  select schem
    from t52c1
    where schem = @p_schem
    into table @data(it_t52c1_selection).

  if sy-subrc <> 0.
    message |Schema { p_schem } not found| type 'S' display like 'E'.
  endif.

*------INITIALIZATION-------*
initialization.

start-of-selection.
  append p_schem to lt_schema_list.
  append p_schem to gt_schema_list.

  " Check if schema has any inner schemas
  perform f_check_inner_schem
    using lt_schema_list.


  " Get and download schemas
  loop at gt_schema_list into data(lv_schema_aux).
    clear it_t52c1.

    select *
      from t52c1
      where schem = @lv_schema_aux
      into table @it_t52c1.

    if sy-subrc = 0.
      clear lt_result.
      perform f_append_schema using it_t52c1.
      perform f_download_schema using lv_schema_aux.
    endif.

    " Get every rule inside the schemas
    clear wa_t52c1.
    loop at it_t52c1 into wa_t52c1.
      if
        wa_t52c1-funco = 'ACTIO' or
        wa_t52c1-funco = 'IF'.

        append wa_t52c1-parm1 to lt_rule_list.

      endif.
    endloop.

  endloop.

  " Get and download rules
  sort lt_rule_list.
  delete adjacent duplicates from lt_rule_list.

  append lines of lt_rule_list to gt_rule_list.

  perform f_check_inner_rules
    using lt_rule_list.

  clear is_rule.
  loop at gt_rule_list into is_rule.

    select *
      from t52c5
      where ccycl = @is_rule
      into table @it_t52c5.

    if sy-subrc = 0.
      clear lt_result.
      perform f_append_rule using it_t52c5.
      perform f_download_rule using is_rule.
    endif.

  endloop.


*------ FORMS -------*

form f_check_inner_schem
  using p_schem_list.

  data lt_new_schemas type table of t52c1.

  loop at p_schem_list into is_schem.
    select parm1
      from t52c1
      where schem = @is_schem
        and funco = 'COPY'
      into table @data(it_schem_aux).

    if sy-subrc = 0.
      append lines of it_schem_aux to lt_new_schemas.
      append lines of it_schem_aux to gt_schema_list.
      clear it_schem_aux.
    endif.
  endloop.

  if lt_new_schemas is not initial.
    perform f_check_inner_schem using lt_new_schemas.
  endif.

endform.

form f_check_inner_rules
  using p_rule_list.

  data lt_new_rules type table of t52c5-ccycl.

  loop at p_rule_list into is_rule.
    select vinfo
      from t52c5
      where ccycl = @is_rule
        and ( vinfo like 'PPCYG____' or vinfo like 'ZGCYG____')
      into table @data(it_rule_aux).

    if sy-subrc = 0.
      loop at it_rule_aux into data(lv_rule_aux).
        if lv_rule_aux(5) = 'PPCYG' or lv_rule_aux(5) = 'ZGCYG'.
          data(lv_formatted_rule) = lv_rule_aux+5(4).
        endif.

        if not line_exists( gt_rule_list[ table_line = lv_formatted_rule ] ).
          append lv_formatted_rule to lt_new_rules.
          append lv_formatted_rule to gt_rule_list.
        endif.
      endloop.
      clear it_rule_aux.
    endif.
  endloop.

  if lt_new_rules is not initial.
    perform f_check_inner_rules using lt_new_rules.
  endif.

endform.

form f_append_schema
  using lt_t52c1.
  append |Schema;Line;Function name;Param 1;Param 2;Param 3;Param 4| to lt_result.
  loop at lt_t52c1 into wa_t52c1.
    append |{ wa_t52c1-schem };{ wa_t52c1-seqno };{ wa_t52c1-funco };{ wa_t52c1-parm1 };{ wa_t52c1-parm2 };{ wa_t52c1-parm3 };{ wa_t52c1-parm4 }| to lt_result.
  endloop.
endform.

form f_append_rule
  using lt_t52c5.
  append |Rule;ES grouping for PCR;Wage type;More details;Next line;Operation| to lt_result.
  loop at lt_t52c5 into wa_t52c5.
    append |{ wa_t52c5-ccycl };{ wa_t52c5-abart };{ wa_t52c5-lgart };{ wa_t52c5-vargt };{ wa_t52c5-seqno };{ wa_t52c5-vinfo }| to lt_result.
  endloop.
endform.

form f_download_schema
  using p_name.

  data(lv_full_path) = |{ p_path }\\schema_{ p_name }.txt|.

  call function 'GUI_DOWNLOAD'
    exporting
      filename = lv_full_path
      filetype = 'ASC'
    tables
      data_tab = lt_result.
endform.

form f_download_rule
  using p_name.

  data(lv_rules_path) = |{ p_path }\\rules|.
  data(lv_path) = |{ lv_rules_path }\\rule_{ p_name }.txt|.
  data rc type i.

  call method cl_gui_frontend_services=>directory_create
    exporting
      directory               = lv_rules_path
    changing
      rc = rc
    exceptions
      cntl_error              = 1
      error_no_gui            = 2
      wrong_parameter         = 3
      directory_create_failed = 4
      others                  = 5.

  call function 'GUI_DOWNLOAD'
    exporting
      filename = lv_path
      filetype = 'ASC'
    tables
      data_tab = lt_result.

endform.
