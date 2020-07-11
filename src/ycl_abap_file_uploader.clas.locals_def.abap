*"* use this source file for any type of declarations (class
*"* definitions, interfaces or type declarations) you need for
*"* components in the private section

CLASS lcl_status DEFINITION.
  PUBLIC SECTION.
    METHODS constructor IMPORTING response TYPE REF TO if_web_http_response.
    METHODS set IMPORTING status TYPE i DEFAULT if_web_http_status=>bad_request
                          log_text TYPE string.

    METHODS valid_table IMPORTING tablename TYPE string
                        RETURNING VALUE(valid) TYPE abap_bool.

    METHODS valid_extension IMPORTING fileext TYPE string
                            RETURNING VALUE(valid) TYPE abap_bool.

  PRIVATE SECTION.
    DATA response TYPE REF TO if_web_http_response.
ENDCLASS.
