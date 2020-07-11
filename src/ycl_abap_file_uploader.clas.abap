CLASS ycl_abap_file_uploader DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_http_service_extension.

  PRIVATE SECTION.

    DATA tablename TYPE string.
    DATA filename TYPE string.
    DATA fileext TYPE string.
    DATA dataoption TYPE string.

    METHODS get_input_field_value IMPORTING name         TYPE string
                                            struct       TYPE data
                                  RETURNING VALUE(value) TYPE string.
    METHODS get_html RETURNING VALUE(ui_html) TYPE string.

    METHODS dynamic_table IMPORTING tablename TYPE string
                                    filedata TYPE string
                          RETURNING VALUE(data_ref) TYPE REF TO data
                          RAISING cx_sy_create_data_error.

    METHODS create_response IMPORTING sap_table_request TYPE string
                            RETURNING VALUE(res)        TYPE string.
    METHODS fill_table IMPORTING status TYPE REF TO lcl_status
                                 filedata TYPE string
                       RETURNING VALUE(done) TYPE abap_bool.
    METHODS unpack_data IMPORTING request TYPE REF TO if_web_http_request
                        RETURNING VALUE(filedata) TYPE string
                        RAISING   cx_web_message_error.
    METHODS extract_filename IMPORTING i_content_item TYPE string
                             EXPORTING filename TYPE string
                                       fileext TYPE string.
ENDCLASS.

CLASS ycl_abap_file_uploader  IMPLEMENTATION.

  METHOD if_http_service_extension~handle_request.

    CASE request->get_method(  ).

      WHEN CONV string( if_web_http_client=>get ).

        response->set_text( create_response( request->get_header_field( 'sap-table-request' ) ) ).

      WHEN CONV string( if_web_http_client=>post ).

        fill_table( status = NEW lcl_status( response )
                    filedata = unpack_data( request ) ).
    ENDCASE.

  ENDMETHOD.

  METHOD create_response.
    IF sap_table_request IS INITIAL.
      res = get_html( ).
      RETURN.
    ENDIF.

    DATA(name_filter) = xco_cp_abap_repository=>object_name->get_filter(
                         xco_cp_abap_sql=>constraint->contains_pattern( to_upper( sap_table_request ) && '%' )  ).

    DATA(objects) = xco_cp_abap_repository=>objects->tabl->where( VALUE #(
                        ( name_filter ) ) )->in( xco_cp_abap=>repository  )->get(  ).

    res = `[`.
    LOOP AT objects INTO DATA(object).
      res &&= |\{ "TABLE_NAME": "{ object->name }" \}|.
      IF sy-tabix NE lines( objects ).
        res &&= `,`.
      ENDIF.
    ENDLOOP.
    res &&= `]`.
  ENDMETHOD.

  METHOD dynamic_table.
    FIELD-SYMBOLS <table_structure> TYPE STANDARD table.

    CREATE DATA data_ref TYPE TABLE OF (tablename).
    ASSIGN data_ref->* TO <table_structure>.

    /ui2/cl_json=>deserialize( EXPORTING json = filedata
                                         pretty_name = /ui2/cl_json=>pretty_mode-none
                               CHANGING data = <table_structure> ).
  ENDMETHOD.

  METHOD fill_table.
    " Load the data to the table via dynamic internal table
    FIELD-SYMBOLS <table_structure> TYPE table.

    CHECK status->valid_table( tablename ) AND status->valid_extension( fileext ).

    TRY.
        DATA(table_ref) = dynamic_table( tablename = tablename
                                         filedata = filedata ).
        ASSIGN table_ref->* TO <table_structure>.

        IF dataoption = `1`.  "if replace, delete the data from the table first
          DELETE FROM (tablename).
        ENDIF.

        INSERT (tablename) FROM TABLE @<table_structure>.
        IF sy-subrc = 0.
          status->set( status = if_web_http_status=>ok
                       log_text = `Table updated successfully` ).
          done = abap_true.
        ENDIF.

      CATCH cx_sy_open_sql_db cx_sy_create_data_error INTO DATA(exception).
        status->set( exception->get_text(  ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD get_input_field_value.
    FIELD-SYMBOLS: <value> TYPE data,
                   <field> TYPE any.

    ASSIGN COMPONENT name  OF STRUCTURE struct TO <field>.
    CHECK <field> IS ASSIGNED.

    ASSIGN <field>->* TO <value>.
    value = condense( <value> ).
  ENDMETHOD.

  METHOD unpack_data.
    " the request comes in with metadata around the actual file data,
    " extract the filename and fileext from this metadata as well as the raw file data.
    SPLIT request->get_text(  ) AT cl_abap_char_utilities=>cr_lf INTO TABLE DATA(content).
    DATA(content_size) = lines( content ).
    IF content_size GE 2.
      extract_filename( EXPORTING i_content_item = content[ 2 ]
                        IMPORTING filename = filename
                                  fileext = fileext ).
    ENDIF.

    " Get rid of the first 4 lines and the last 9 lines
    LOOP AT content FROM 5 TO  ( content_size - 9 ) ASSIGNING FIELD-SYMBOL(<content_item>).  " put it all back together again humpdy dumpdy....
      filedata &&= <content_item>.
    ENDLOOP.

    " Unpack input field values such as tablename, dataoption, etc.
    DATA(lr_ui) = /ui2/cl_json=>generate( request->get_form_field( `filetoupload-data` ) ).
    IF lr_ui IS BOUND.
      ASSIGN lr_ui->* TO FIELD-SYMBOL(<ui_data>).
      tablename = get_input_field_value( name = `TABLENAME` struct = <ui_data> ).
      dataoption = get_input_field_value( name = `DATAOPTION` struct = <ui_data> ).
    ENDIF.
  ENDMETHOD.

  METHOD extract_filename.
    CLEAR: filename,
           fileext.

    SPLIT i_content_item AT ';' INTO TABLE DATA(content_dis).
    ASSIGN content_dis[ 3 ] TO FIELD-SYMBOL(<content_dis_item>).
    CHECK sy-subrc = 0.

    SPLIT <content_dis_item> AT '=' INTO DATA(fn) filename.
    REPLACE ALL OCCURRENCES OF `"` IN filename WITH space.
    CONDENSE filename NO-GAPS.
    SPLIT filename AT '.' INTO filename fileext.
  ENDMETHOD.

  METHOD get_html.
    ui_html =
    |<!DOCTYPE HTML> \n| &&
     |<html> \n| &&
     |<head> \n| &&
     |    <meta http-equiv="X-UA-Compatible" content="IE=edge"> \n| &&
     |    <meta http-equiv='Content-Type' content='text/html;charset=UTF-8' /> \n| &&
     |    <title>ABAP File Uploader</title> \n| &&
     |    <script id="sap-ui-bootstrap" src="https://sapui5.hana.ondemand.com/resources/sap-ui-core.js" \n| &&
     |        data-sap-ui-theme="sap_fiori_3_dark" data-sap-ui-xx-bindingSyntax="complex" data-sap-ui-compatVersion="edge" \n| &&
     |        data-sap-ui-async="true"> \n| &&
     |    </script> \n| &&
     |    <script> \n| &&
     |        sap.ui.require(['sap/ui/core/Core'], (oCore, ) => \{ \n| &&
     | \n| &&
     |            sap.ui.getCore().loadLibrary("sap.f", \{ \n| &&
     |                async: true \n| &&
     |            \}).then(() => \{ \n| &&
     |                let shell = new sap.f.ShellBar("shell") \n| &&
     |                shell.setTitle("ABAP File Uploader") \n| &&
     |                shell.setShowCopilot(true) \n| &&
     |                shell.setShowSearch(true) \n| &&
     |                shell.setShowNotifications(true) \n| &&
     |                shell.setShowProductSwitcher(true) \n| &&
     |                shell.placeAt("uiArea") \n| &&
     |                sap.ui.getCore().loadLibrary("sap.ui.layout", \{ \n| &&
     |                    async: true \n| &&
     |                \}).then(() => \{ \n| &&
     |                    let layout = new sap.ui.layout.VerticalLayout("layout") \n| &&
     |                    layout.placeAt("uiArea") \n| &&
     |                    let line2 = new sap.ui.layout.HorizontalLayout("line2") \n| &&
     |                    let line3 = new sap.ui.layout.HorizontalLayout("line3") \n| &&
     |                    let line4 = new sap.ui.layout.HorizontalLayout("line4") \n| &&
     |                    sap.ui.getCore().loadLibrary("sap.m", \{ \n| &&
     |                        async: true \n| &&
     |                    \}).then(() => \{\}) \n| &&
     |                    let button = new sap.m.Button("button") \n| &&
     |                    button.setText("Upload File") \n| &&
     |                    button.attachPress(function () \{ \n| &&
     |                        let oFileUploader = oCore.byId("fileToUpload") \n| &&
     |                        if (!oFileUploader.getValue()) \{ \n| &&
     |                            sap.m.MessageToast.show("Choose a file first") \n| &&
     |                            return \n| &&
     |                        \} \n| &&
     |                        let oInput = oCore.byId("tablename") \n| &&
     |                        let oGroup = oCore.byId("grpDataOptions") \n| &&
     |                        if (!oInput.getValue())\{ \n| &&
     |                            sap.m.MessageToast.show("Target Table is Required") \n| &&
     |                            return \n| &&
     |                        \} \n| &&
     |                       let param = oCore.byId("uploadParam") \n| &&
     |                       param.setValue( oInput.getValue() ) \n| &&
     |                       oFileUploader.getParameters() \n| &&
     |                       oFileUploader.setAdditionalData(JSON.stringify(\{tablename: oInput.getValue(), \n| &&
     |                           dataOption: oGroup.getSelectedIndex() \})) \n| &&
     |                       oFileUploader.upload() \n| &&
     |                    \}) \n| &&
     |                    let input = new sap.m.Input("tablename") \n| &&
     |                    input.placeAt("layout") \n| &&
     |                    input.setRequired(true) \n| &&
     |                    input.setWidth("600px") \n| &&
     |                    input.setPlaceholder("Target ABAP Table") \n| &&
     |                    input.setShowSuggestion(true) \n| &&
     |                    input.attachSuggest(function (oEvent)\{ \n| &&
     |                      jQuery.ajax(\{headers: \{ "sap-table-request": oEvent.getParameter("suggestValue") \n | &&
     |                          \}, \n| &&
     |                         error: function(oErr)\{ alert( JSON.stringify(oErr))\}, timeout: 30000, method:"GET",dataType: "json",success: function(myJSON) \{ \n| &&
 "   |                      alert( 'test' ) \n| &&
     |                      let input = oCore.byId("tablename") \n | &&
     |                      input.destroySuggestionItems() \n | &&
     |                      for (var i = 0; i < myJSON.length; i++) \{ \n | &&
     |                          input.addSuggestionItem(new sap.ui.core.Item(\{ \n| &&
     |                              text: myJSON[i].TABLE_NAME  \n| &&
     |                          \})); \n| &&
     |                      \} \n| &&
     |                    \} \}) \n| &&
     |                    \}) \n| &&
     |                    line2.placeAt("layout") \n| &&
     |                    line3.placeAt("layout") \n| &&
     |                    line4.placeAt("layout") \n| &&
     |                    let groupDataOptions = new sap.m.RadioButtonGroup("grpDataOptions") \n| &&
     |                    let lblGroupDataOptions = new sap.m.Label("lblDataOptions") \n| &&
     |                    lblGroupDataOptions.setLabelFor(groupDataOptions) \n| &&
     |                    lblGroupDataOptions.setText("Data Upload Options") \n| &&
     |                    lblGroupDataOptions.placeAt("line3") \n| &&
     |                    groupDataOptions.placeAt("line4") \n| &&
     |                    rbAppend = new sap.m.RadioButton("rbAppend") \n| &&
     |                    rbReplace = new sap.m.RadioButton("rbReplace") \n| &&
     |                    rbAppend.setText("Append") \n| &&
     |                    rbReplace.setText("Replace") \n| &&
     |                    groupDataOptions.addButton(rbAppend) \n| &&
     |                    groupDataOptions.addButton(rbReplace) \n| &&
     |                    rbAppend.setGroupName("grpDataOptions") \n| &&
     |                    rbReplace.setGroupName("grpDataOptions") \n| &&
     |                    sap.ui.getCore().loadLibrary("sap.ui.unified", \{ \n| &&
     |                        async: true \n| &&
     |                    \}).then(() => \{ \n| &&
     |                        var fileUploader = new sap.ui.unified.FileUploader( \n| &&
     |                            "fileToUpload") \n| &&
     |                        fileUploader.setFileType("json") \n| &&
     |                        fileUploader.setWidth("400px") \n| &&
     |                        let param = new sap.ui.unified.FileUploaderParameter("uploadParam") \n| &&
     |                        param.setName("tablename") \n| &&
     |                        fileUploader.addParameter(param) \n| &&
     |                        fileUploader.placeAt("line2") \n| &&
     |                        button.placeAt("line2") \n| &&
     |                        fileUploader.setPlaceholder( \n| &&
     |                            "Choose File for Upload...") \n| &&
     |                        fileUploader.attachUploadComplete(function (oEvent) \{ \n| &&
     |                           alert(oEvent.getParameters().response)  \n| &&
     |                       \})   \n| &&
     | \n| &&
     |                    \}) \n| &&
     |                \}) \n| &&
     |            \}) \n| &&
     |        \}) \n| &&
     |    </script> \n| &&
     |</head> \n| &&
     |<body class="sapUiBody"> \n| &&
     |    <div id="uiArea"></div> \n| &&
     |</body> \n| &&
     | \n| &&
     |</html> |.
  ENDMETHOD.

ENDCLASS.
