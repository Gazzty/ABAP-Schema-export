*&---------------------------------------------------------------------*
*& Report Y_SCHEMA_EXPORT
*&---------------------------------------------------------------------*
*& Author: Gustavo T. Muiños
*& Description: Export PE01 schemas and related rules to text files
*& Note: Uses dynamic SQL for system independence
*&---------------------------------------------------------------------*
REPORT y_schema_export.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES: gtyp_schma TYPE c LENGTH 4,
       gtyp_rule  TYPE c LENGTH 4.

TYPES: BEGIN OF ty_object,
         name TYPE c LENGTH 4,
         type TYPE c LENGTH 1,  " S = Schema, R = Rule
       END OF ty_object.

TYPES: tt_objects TYPE STANDARD TABLE OF ty_object WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Data declarations
*----------------------------------------------------------------------*
DATA: gt_objects     TYPE tt_objects,
      gt_processed   TYPE tt_objects,
      gv_output_path TYPE string.

*----------------------------------------------------------------------*
* Initialization - Register GUI services
*----------------------------------------------------------------------*
INITIALIZATION.
  " No GUI initialization here - will be done at execution time

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_schma TYPE gtyp_schma OBLIGATORY.
  PARAMETERS: p_path  TYPE string LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* At Selection Screen - Value Help for Schema
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_schma.
  PERFORM f4_schema.

*----------------------------------------------------------------------*
* At Selection Screen - File Dialog for output path
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  PERFORM f4_folder.

*----------------------------------------------------------------------*
* Start of Selection
*----------------------------------------------------------------------*
START-OF-SELECTION.
  " Validate and prepare output path
  gv_output_path = p_path.
  IF gv_output_path IS INITIAL.
    MESSAGE 'Please specify an output path' TYPE 'E'.
    RETURN.
  ENDIF.

  " Ensure path ends with separator
  IF NOT gv_output_path CP '*\'.
    CONCATENATE gv_output_path '\' INTO gv_output_path.
  ENDIF.

  " Clear tables
  CLEAR: gt_objects, gt_processed.

  " Add root schema to objects list
  APPEND VALUE ty_object( name = p_schma type = 'S' ) TO gt_objects.

  " Process all schemas (only schemas for now, rules follow same structure)
  PERFORM process_all_objects.

  " Export all collected objects to single file
  PERFORM export_all_objects.

  MESSAGE |Export completed. { lines( gt_processed ) } objects processed.| TYPE 'S'.

*&---------------------------------------------------------------------*
*& Form F4_SCHEMA
*&---------------------------------------------------------------------*
FORM f4_schema.
  DATA: lt_return TYPE STANDARD TABLE OF ddshretval.

  CALL FUNCTION 'F4IF_FIELD_VALUE_REQUEST'
    EXPORTING
      tabname     = 'T52C0'
      fieldname   = 'SCHEM'
      dynpprog    = sy-repid
      dynpnr      = sy-dynnr
      dynprofield = 'P_SCHMA'
    TABLES
      return_tab  = lt_return
    EXCEPTIONS
      OTHERS      = 1.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form F4_FOLDER
*&---------------------------------------------------------------------*
FORM f4_folder.
  DATA: lv_path     TYPE string,
        lv_title    TYPE string VALUE 'Select Output Folder',
        lv_filename TYPE string,
        lv_fullpath TYPE string.

  CALL METHOD cl_gui_frontend_services=>file_save_dialog
    EXPORTING
      window_title      = lv_title
      default_extension = 'txt'
      default_file_name = 'schema'
      initial_directory = 'C:\'
    CHANGING
      filename          = lv_filename
      path              = lv_path
      fullpath          = lv_fullpath
    EXCEPTIONS
      OTHERS            = 1.

  IF sy-subrc = 0 AND lv_path IS NOT INITIAL.
    p_path = lv_path.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form PROCESS_ALL_OBJECTS
*&---------------------------------------------------------------------*
FORM process_all_objects.
  DATA: ls_object  TYPE ty_object,
        lt_new_obj TYPE tt_objects,
        lv_index   TYPE i.

  lv_index = 1.

  " Process loop - continue until no new objects
  WHILE lv_index <= lines( gt_objects ).
    READ TABLE gt_objects INTO ls_object INDEX lv_index.

    " Check if already processed
    READ TABLE gt_processed WITH KEY name = ls_object-name
                                     type = ls_object-type TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      " Mark as processed
      APPEND ls_object TO gt_processed.

      CLEAR lt_new_obj.

      " Find referenced objects based on type
      IF ls_object-type = 'S'.
        " Schema: search in T52C1 for ACTIO (rules) and COPY (schemas)
        PERFORM find_schema_references USING ls_object-name CHANGING lt_new_obj.
      ELSE.
        " Rule: search in T52C5 for NEXTR (other rules)
        PERFORM find_rule_references USING ls_object-name CHANGING lt_new_obj.
      ENDIF.

      " Add new objects to processing list (if not already there)
      LOOP AT lt_new_obj INTO DATA(ls_new).
        READ TABLE gt_objects WITH KEY name = ls_new-name
                                       type = ls_new-type TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_new TO gt_objects.
        ENDIF.
      ENDLOOP.
    ENDIF.

    lv_index = lv_index + 1.
  ENDWHILE.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FIND_SCHEMA_REFERENCES
*& Reads schema lines and finds referenced schemas (COPY) and rules (ACTIO)
*&---------------------------------------------------------------------*
FORM find_schema_references USING    iv_schema TYPE gtyp_schma
                            CHANGING ct_objects TYPE tt_objects.

  DATA: lt_data    TYPE REF TO data,
        lv_funco   TYPE c LENGTH 10,
        lv_parm1   TYPE c LENGTH 20.

  FIELD-SYMBOLS: <lt_table>  TYPE STANDARD TABLE,
                 <ls_line>   TYPE any,
                 <fv_field>  TYPE any.

  " Create dynamic table reference for T52C1
  TRY.
      CREATE DATA lt_data TYPE STANDARD TABLE OF t52c1.
      ASSIGN lt_data->* TO <lt_table>.

      " Select schema lines
      SELECT * FROM t52c1
        INTO TABLE <lt_table>
        WHERE schem = iv_schema.

      LOOP AT <lt_table> ASSIGNING <ls_line>.
        CLEAR: lv_funco, lv_parm1.

        " Get FUNCO field
        ASSIGN COMPONENT 'FUNCO' OF STRUCTURE <ls_line> TO <fv_field>.
        IF sy-subrc = 0.
          lv_funco = <fv_field>.
        ENDIF.

        " Get PARM1 field
        ASSIGN COMPONENT 'PARM1' OF STRUCTURE <ls_line> TO <fv_field>.
        IF sy-subrc = 0.
          lv_parm1 = <fv_field>.
        ENDIF.

        " If FUNCO = ACTIO -> search as rule in T52C5
        IF lv_funco = 'ACTIO' AND lv_parm1 IS NOT INITIAL.
          IF strlen( lv_parm1 ) >= 4.
            APPEND VALUE ty_object( name = lv_parm1(4) type = 'R' ) TO ct_objects.
          ENDIF.
        ENDIF.

        " If FUNCO = COPY -> search as schema in T52C1 (recursive)
        IF lv_funco = 'COPY' AND lv_parm1 IS NOT INITIAL.
          IF strlen( lv_parm1 ) >= 4.
            APPEND VALUE ty_object( name = lv_parm1(4) type = 'S' ) TO ct_objects.
          ENDIF.
        ENDIF.
      ENDLOOP.

    CATCH cx_root.
      " Error handling - table structure may be different
      WRITE: / 'Error reading schema lines for:', iv_schema.
  ENDTRY.

  " Remove duplicates
  SORT ct_objects BY name type.
  DELETE ADJACENT DUPLICATES FROM ct_objects COMPARING name type.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FIND_RULE_REFERENCES
*& Reads rule lines from T52C5 and finds referenced rules (NEXTR)
*&---------------------------------------------------------------------*
FORM find_rule_references USING    iv_rule TYPE gtyp_rule
                          CHANGING ct_objects TYPE tt_objects.

  DATA: lt_data    TYPE REF TO data,
        lv_vession TYPE c LENGTH 10,
        lv_vargt   TYPE c LENGTH 40,
        lv_rule    TYPE c LENGTH 4,
        lv_where   TYPE string.

  FIELD-SYMBOLS: <lt_table>  TYPE STANDARD TABLE,
                 <ls_line>   TYPE any,
                 <fv_field>  TYPE any.

  " Create dynamic table reference for T52C5
  TRY.
      CREATE DATA lt_data TYPE STANDARD TABLE OF t52c5.
      ASSIGN lt_data->* TO <lt_table>.

      " Get structure to find key field dynamically
      DATA(lo_struct) = CAST cl_abap_structdescr(
          cl_abap_typedescr=>describe_by_name( 'T52C5' ) ).
      DATA(lt_keys) = lo_struct->get_components( ).

      " Try first field after MANDT as key
      LOOP AT lt_keys INTO DATA(ls_key) WHERE name <> 'MANDT'.
        TRY.
            lv_where = |{ ls_key-name } = '{ iv_rule }'|.
            SELECT * FROM t52c5 INTO TABLE <lt_table>
              WHERE (lv_where).
            IF lines( <lt_table> ) > 0.
              EXIT. " Found data
            ENDIF.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.
      ENDLOOP.

      LOOP AT <lt_table> ASSIGNING <ls_line>.
        CLEAR: lv_vession, lv_vargt.

        " Get VESSION field (operation/function)
        ASSIGN COMPONENT 'VESSION' OF STRUCTURE <ls_line> TO <fv_field>.
        IF sy-subrc = 0.
          lv_vession = <fv_field>.
        ENDIF.

        " Get VARGT field (arguments/parameters)
        ASSIGN COMPONENT 'VARGT' OF STRUCTURE <ls_line> TO <fv_field>.
        IF sy-subrc = 0.
          lv_vargt = <fv_field>.
        ENDIF.

        " Check for NEXTR operation (calls another rule)
        " Example: "PPCYGZA37   NEXTR A" - rule reference is in the first part
        IF lv_vession = 'NEXTR' AND lv_vargt IS NOT INITIAL.
          " Extract rule name from VARGT (first 4 characters)
          IF strlen( lv_vargt ) >= 4.
            lv_rule = lv_vargt(4).
            IF lv_rule(1) CA 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.
              APPEND VALUE ty_object( name = lv_rule type = 'R' ) TO ct_objects.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDLOOP.

    CATCH cx_root.
      " Error handling - table structure may be different
      WRITE: / 'Error reading rule lines for:', iv_rule.
  ENDTRY.

  " Remove duplicates
  SORT ct_objects BY name type.
  DELETE ADJACENT DUPLICATES FROM ct_objects COMPARING name type.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form EXPORT_ALL_OBJECTS
*& Exports all objects to a SINGLE file (one authentication only)
*&---------------------------------------------------------------------*
FORM export_all_objects.
  DATA: lv_filename    TYPE string,
        lt_all_content TYPE STANDARD TABLE OF string,
        lt_content     TYPE STANDARD TABLE OF string,
        lv_count_s     TYPE i,
        lv_count_r     TYPE i.

  " Build single file with all content - header
  APPEND |*&=====================================================================*| TO lt_all_content.
  APPEND |*& PE01 SCHEMA EXPORT - { p_schma }| TO lt_all_content.
  APPEND |*& Export Date: { sy-datum DATE = USER } { sy-uzeit TIME = USER }| TO lt_all_content.
  APPEND |*& Total Objects: { lines( gt_processed ) }| TO lt_all_content.
  APPEND |*&=====================================================================*| TO lt_all_content.
  APPEND '' TO lt_all_content.

  " Export each object into the single file
  LOOP AT gt_processed INTO DATA(ls_object).
    CLEAR lt_content.

    IF ls_object-type = 'S'.
      PERFORM build_schema_content USING ls_object-name CHANGING lt_content.
      lv_count_s = lv_count_s + 1.
    ELSE.
      PERFORM build_rule_content USING ls_object-name CHANGING lt_content.
      lv_count_r = lv_count_r + 1.
    ENDIF.

    " Only add if we have content
    IF lines( lt_content ) > 5.
      " Add separator before each object (except first)
      IF lines( lt_all_content ) > 6.
        APPEND '' TO lt_all_content.
        APPEND |*&---------------------------------------------------------------------*| TO lt_all_content.
        APPEND '' TO lt_all_content.
      ENDIF.

      " Append content
      APPEND LINES OF lt_content TO lt_all_content.
    ENDIF.
  ENDLOOP.

  " Add footer
  APPEND '' TO lt_all_content.
  APPEND |*&=====================================================================*| TO lt_all_content.
  APPEND |*& END OF EXPORT| TO lt_all_content.
  APPEND |*& Schemas: { lv_count_s } / Rules: { lv_count_r }| TO lt_all_content.
  APPEND |*&=====================================================================*| TO lt_all_content.

  " Build single filename
  CONCATENATE gv_output_path p_schma '_EXPORT.txt' INTO lv_filename.

  " Single download - only ONE authentication required
  PERFORM download_file USING lv_filename lt_all_content.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form BUILD_SCHEMA_CONTENT
*&---------------------------------------------------------------------*
FORM build_schema_content USING    iv_schema TYPE gtyp_schma
                          CHANGING ct_content TYPE STANDARD TABLE.

  DATA: lt_data    TYPE REF TO data,
        lv_line    TYPE string.

  FIELD-SYMBOLS: <lt_table>  TYPE STANDARD TABLE,
                 <ls_line>   TYPE any,
                 <ls_text>   TYPE any,
                 <fv_field>  TYPE any.

  " Header information
  APPEND |*&---------------------------------------------------------------------*| TO ct_content.
  APPEND |*& Schema: { iv_schema }| TO ct_content.

  " Try to get schema description from T52CE
  TRY.
      CREATE DATA lt_data TYPE t52ce.
      ASSIGN lt_data->* TO <ls_text>.

      " Try dynamic SELECT with different possible key fields
      DATA(lo_text_struct) = CAST cl_abap_structdescr(
          cl_abap_typedescr=>describe_by_name( 'T52CE' ) ).
      DATA(lt_text_keys) = lo_text_struct->get_components( ).

      LOOP AT lt_text_keys INTO DATA(ls_tkey) WHERE name <> 'MANDT' AND name <> 'SPRSL'.
        TRY.
            DATA(lv_text_where) = |{ ls_tkey-name } = '{ iv_schema }'|.
            SELECT SINGLE * FROM t52ce INTO <ls_text>
              WHERE (lv_text_where).
            IF sy-subrc = 0.
              EXIT.
            ENDIF.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.
      ENDLOOP.

      IF sy-subrc = 0.
        ASSIGN COMPONENT 'STEXT' OF STRUCTURE <ls_text> TO <fv_field>.
        IF sy-subrc = 0 AND <fv_field> IS NOT INITIAL.
          APPEND |*& Description: { <fv_field> }| TO ct_content.
        ENDIF.
      ENDIF.
    CATCH cx_root.
      " Ignore errors getting description
  ENDTRY.

  APPEND |*& Export Date: { sy-datum DATE = USER }| TO ct_content.
  APPEND |*&---------------------------------------------------------------------*| TO ct_content.
  APPEND '' TO ct_content.

  " Get schema lines
  TRY.
      CREATE DATA lt_data TYPE STANDARD TABLE OF t52c1.
      ASSIGN lt_data->* TO <lt_table>.

      SELECT * FROM t52c1 INTO TABLE <lt_table>
        WHERE schem = iv_schema.

      LOOP AT <lt_table> ASSIGNING <ls_line>.
        " Build output line using all available components
        PERFORM build_line_from_structure USING <ls_line> CHANGING lv_line.
        APPEND lv_line TO ct_content.
      ENDLOOP.

    CATCH cx_root.
      APPEND |Error reading schema data| TO ct_content.
  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form BUILD_RULE_CONTENT
*& Build rule content from T52C5 using dynamic SQL approach
*&---------------------------------------------------------------------*
FORM build_rule_content USING    iv_rule TYPE gtyp_rule
                        CHANGING ct_content TYPE STANDARD TABLE.

  DATA: lt_data     TYPE REF TO data,
        lv_line     TYPE string,
        lv_where    TYPE string.

  FIELD-SYMBOLS: <lt_table>  TYPE STANDARD TABLE,
                 <ls_line>   TYPE any.

  " Header information
  APPEND |*&---------------------------------------------------------------------*| TO ct_content.
  APPEND |*& Rule (PCR): { iv_rule }| TO ct_content.
  APPEND |*& Export Date: { sy-datum DATE = USER }| TO ct_content.
  APPEND |*&---------------------------------------------------------------------*| TO ct_content.
  APPEND '' TO ct_content.

  " Get rule lines from T52C5 using dynamic WHERE
  TRY.
      CREATE DATA lt_data TYPE STANDARD TABLE OF t52c5.
      ASSIGN lt_data->* TO <lt_table>.

      " Get structure to find key field dynamically
      DATA(lo_struct) = CAST cl_abap_structdescr(
          cl_abap_typedescr=>describe_by_name( 'T52C5' ) ).
      DATA(lt_keys) = lo_struct->get_components( ).

      " Try first field after MANDT as key
      LOOP AT lt_keys INTO DATA(ls_key) WHERE name <> 'MANDT'.
        TRY.
            lv_where = |{ ls_key-name } = '{ iv_rule }'|.
            SELECT * FROM t52c5 INTO TABLE <lt_table>
              WHERE (lv_where).
            IF lines( <lt_table> ) > 0.
              EXIT. " Found data
            ENDIF.
          CATCH cx_root.
            CONTINUE.
        ENDTRY.
      ENDLOOP.

      LOOP AT <lt_table> ASSIGNING <ls_line>.
        PERFORM build_line_from_structure USING <ls_line> CHANGING lv_line.
        APPEND lv_line TO ct_content.
      ENDLOOP.

    CATCH cx_root.
      APPEND |Rule data not available or table structure differs| TO ct_content.
  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form BUILD_LINE_FROM_STRUCTURE
*& Build a formatted line from any structure using RTTS
*&---------------------------------------------------------------------*
FORM build_line_from_structure USING    is_struct TYPE any
                               CHANGING cv_line   TYPE string.

  DATA: lo_struct TYPE REF TO cl_abap_structdescr,
        lt_comp   TYPE cl_abap_structdescr=>component_table.

  FIELD-SYMBOLS: <ls_comp>  TYPE abap_componentdescr,
                 <fv_field> TYPE any.

  CLEAR cv_line.

  " Get structure description
  lo_struct ?= cl_abap_typedescr=>describe_by_data( is_struct ).
  lt_comp = lo_struct->get_components( ).

  " Build line from all components
  LOOP AT lt_comp ASSIGNING <ls_comp>.
    " Skip MANDT and internal fields
    CHECK <ls_comp>-name <> 'MANDT' AND <ls_comp>-name(1) <> '.'.

    ASSIGN COMPONENT <ls_comp>-name OF STRUCTURE is_struct TO <fv_field>.
    IF sy-subrc = 0.
      IF cv_line IS INITIAL.
        cv_line = |{ <fv_field> }|.
      ELSE.
        cv_line = |{ cv_line }\t{ <fv_field> }|.
      ENDIF.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form DOWNLOAD_FILE
*&---------------------------------------------------------------------*
FORM download_file USING iv_filename TYPE string
                         it_content  TYPE STANDARD TABLE.

  DATA: lv_filesize TYPE i,
        lv_filename TYPE string.

  lv_filename = iv_filename.

  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      filename                = lv_filename
      filetype                = 'ASC'
      write_bom               = abap_true
      confirm_overwrite       = space
    IMPORTING
      filelength              = lv_filesize
    TABLES
      data_tab                = it_content
    EXCEPTIONS
      file_write_error        = 1
      no_batch                = 2
      gui_refuse_filetransfer = 3
      invalid_type            = 4
      no_authority            = 5
      unknown_error           = 6
      OTHERS                  = 7.

  IF sy-subrc <> 0.
    MESSAGE |Error writing file: { iv_filename }| TYPE 'W'.
  ELSE.
    WRITE: / |Created: { iv_filename } ({ lv_filesize } bytes)|.
  ENDIF.

ENDFORM.
