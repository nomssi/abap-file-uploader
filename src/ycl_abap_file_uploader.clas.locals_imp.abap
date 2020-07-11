*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations

CLASS lcl_status IMPLEMENTATION.

  METHOD set.
    response->set_status( i_code = status
                          i_reason = log_text ).
    response->set_text( log_text ).
  ENDMETHOD.

  METHOD constructor.
    me->response = response.
  ENDMETHOD.

  METHOD valid_extension.
    " Check file extension is valid, only json today.
    IF fileext <> `json`.
      set( `File type not supported` ).
      valid = abap_false.
    ELSE.
      valid = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD valid_table.
    " Check table name is valid.
    IF tablename IS INITIAL OR
      NOT xco_cp_abap_repository=>object->tabl->database_table->for( CONV #( tablename ) )->exists(  ).
      set( |Table name { tablename } not valid or does not exist|  ).
      valid = abap_false.
    ELSE.
      valid = abap_true.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
