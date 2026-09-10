unit uphosphorlang;

{ GENERATED FILE -- DO NOT EDIT.

  Rewrite it with:  python tools/gen-keywords.py <path-to-Phosphor-checkout>

  Every name here is a fact about the Phosphor repository, not about this one:
  the keyword lists come from TPhosphorCompiler.IsReservedWord and the built-in
  lists from the Reg.Add registrations in engine/libs, host/packages and
  host/gui/libs. Editing this file by hand puts those facts in two places, and
  the copy that is edited is the one that goes stale.

  The three built-in tiers are not interchangeable, which is why they are three
  lists rather than one. Core is always present. Package names exist only because
  the console host links every package -- another host need not. GUI names exist
  only where a graphical session was reachable when the program started, so a
  program that calls one is portable in a way `print` is not.

  Lookup is case-insensitive: Phosphor lowercases every identifier as it is
  scanned (engine/PhosphorLexer.pas:392), so `PrintLn` and `println` are one word.
  A name's type suffix ($ % @ ?) is PART of the name and is kept -- `left$` is the
  word, not `left` followed by an operator.
}

{$mode objfpc}{$H+}

interface

type
  { Which host a built-in needs. Ordered by how universally available it is, so
    a completion list can be filtered with a single <= test. }
  TPhosphorTier = (ptCore, ptPackage, ptGui);

  { A plain open array of words. Declared here rather than using the RTL's
    TStringArray so this unit compiles unchanged against an FPC that predates it. }
  TPhosphorWordList = array of String;

function IsPhosphorKeyword(const AWord: String): Boolean;
function IsPhosphorOperatorWord(const AWord: String): Boolean;
function IsPhosphorLiteralWord(const AWord: String): Boolean;
function IsPhosphorBuiltin(const AWord: String): Boolean;
function PhosphorBuiltinTier(const AWord: String; out ATier: TPhosphorTier): Boolean;

{ The raw lists, for a completion box or a documentation lookup. Sorted, lower
  case, suffixes included. Do not modify them in place. }
function PhosphorKeywords: TPhosphorWordList;
function PhosphorOperatorWords: TPhosphorWordList;
function PhosphorLiteralWords: TPhosphorWordList;
function PhosphorBuiltins(ATier: TPhosphorTier): TPhosphorWordList;

const
  { What this unit was generated from, so a mismatch is legible in a bug report
    rather than a mystery. }
  PhosphorLangSource = 'Phosphor engine/libs + host/packages + host/gui/libs';
  PhosphorKeywordCount = 53;
  PhosphorBuiltinCoreCount = 538;
  PhosphorBuiltinPackageCount = 181;
  PhosphorBuiltinGuiCount = 426;

implementation

uses
  Classes, SysUtils;


const
  KeywordWords: array[0..52] of String = (
    'append', 'as', 'binary', 'break', 'breakpoint', 'call', 'case', 'close',
    'const', 'continue', 'data', 'dim', 'do', 'else', 'elseif', 'end',
    'endfunction', 'endif', 'endselect', 'endwhile', 'error', 'for',
    'function', 'gosub', 'goto', 'if', 'input', 'let', 'line', 'local',
    'loop', 'next', 'on', 'open', 'output', 'print', 'println', 'read',
    'repeat', 'restore', 'resume', 'return', 'seek', 'select', 'step', 'swap',
    'then', 'to', 'trace', 'until', 'using', 'wend', 'while'
  );

  OperatorWords: array[0..3] of String = (
    'and', 'mod', 'not', 'or'
  );

  LiteralWords: array[0..2] of String = (
    'false', 'null', 'true'
  );

  BuiltinCoreWords: array[0..537] of String = (
    'abs', 'acos', 'acosh', 'alarmspath$', 'alcase$', 'alphacolor',
    'altseparator$', 'arr_free', 'arr_get', 'arr_set@', 'arraysize',
    'arraytype', 'arraytypename$', 'asc', 'asin', 'asinh', 'atan', 'atan2',
    'atanh', 'aucase$', 'bin$', 'buffer_clone@', 'buffer_copy',
    'buffer_equal', 'buffer_fill', 'buffer_fillrange', 'buffer_free',
    'buffer_fromstr@', 'buffer_get', 'buffer_getdbl', 'buffer_getint',
    'buffer_getsng', 'buffer_getuint', 'buffer_indexof', 'buffer_len',
    'buffer_new@', 'buffer_resize', 'buffer_set', 'buffer_setdbl',
    'buffer_setint', 'buffer_setsng', 'buffer_slice$', 'buffer_tostr$',
    'buffer_write', 'byteat', 'bytelen', 'bytemid$', 'bytestr$', 'cachepath$',
    'callfunc', 'callfunc$', 'callfunc%', 'callfunc?', 'callfunc@',
    'camerapath$', 'center$', 'cfg_autosave@', 'cfg_clear@', 'cfg_delete@',
    'cfg_deletekey@', 'cfg_exists', 'cfg_filename$', 'cfg_get$', 'cfg_getb',
    'cfg_getbs', 'cfg_getn', 'cfg_getns', 'cfg_gets$', 'cfg_haskey',
    'cfg_keycount', 'cfg_keys$', 'cfg_modified', 'cfg_open@',
    'cfg_open_auto@', 'cfg_path$', 'cfg_reload@', 'cfg_save',
    'cfg_section_delete@', 'cfg_section_exists', 'cfg_sectioncount',
    'cfg_sections$', 'cfg_set@', 'cfg_setb@', 'cfg_setbs@', 'cfg_setn@',
    'cfg_setns@', 'cfg_sets@', 'changefileext$', 'chdir', 'chr$', 'cint',
    'classname$', 'cmpval', 'color', 'colortostr$', 'containsstr',
    'containstext', 'copytext$', 'cos', 'cosh', 'count', 'countstr', 'date',
    'date$', 'datetime$', 'datetimetostr$', 'datetostr$', 'dayof',
    'dayofthemonth', 'dayoftheweek', 'dayoftheyear', 'dayofweek',
    'daysbetween', 'daysinamonth', 'daysinayear', 'daysinmonth', 'daysinyear',
    'dayspan', 'degtorad', 'delete$', 'dict@', 'dict_clear@', 'dict_count',
    'dict_exists', 'dict_get', 'dict_get$', 'dict_get%', 'dict_get?',
    'dict_get@', 'dict_getdef', 'dict_getdef$', 'dict_getdef?',
    'dict_getdef@', 'dict_haskey', 'dict_key$', 'dict_remove', 'dict_set@',
    'dict_type', 'dict_typename$', 'dict_typeof', 'dict_typeof$', 'dim@',
    'dir_copy', 'dir_create', 'dir_delete', 'dir_exists',
    'dir_getcreationtime', 'dir_getcurrent$', 'dir_getdirectories$',
    'dir_getentries$', 'dir_getfiles$', 'dir_getlastaccesstime',
    'dir_getlastwritetime', 'dir_getparent$', 'dir_isempty',
    'dir_isrelativepath', 'dir_move', 'dir_setcreationtime', 'dir_setcurrent',
    'dir_setlastaccesstime', 'dir_setlastwritetime', 'dirseparator$',
    'documentspath$', 'downloadspath$', 'encodedate', 'endsstr', 'endstext',
    'environ$', 'eof', 'erl', 'err', 'err_clear', 'errmsg$', 'error', 'exp',
    'extractfileext$', 'extractfilename$', 'extractfilepath$',
    'file_appendalltext', 'file_copy', 'file_createempty', 'file_delete',
    'file_exists', 'file_getcreationtime', 'file_getlastaccesstime',
    'file_getlastwritetime', 'file_getsize', 'file_move',
    'file_readallbytes@', 'file_readalltext$', 'file_setcreationtime',
    'file_setlastaccesstime', 'file_setlastwritetime', 'file_writeallbytes',
    'file_writealltext', 'fileexists', 'fix', 'forcedirectories',
    'formatdatetime$', 'formatsettings', 'formatsettings$', 'frac',
    'funcexists?', 'gettime', 'guidfilename$', 'handlemessage', 'hex$',
    'homepath$', 'hourof', 'hoursbetween', 'hourspan', 'incday', 'inchour',
    'incmillisecond', 'incminute', 'incmonth', 'incsecond', 'incweek',
    'incyear', 'input$', 'insert$', 'instr', 'instrrev', 'int', 'ioerror',
    'iostrerror$', 'isalnum', 'isalpha', 'isam', 'isassigned', 'isdigits',
    'isinfinite', 'isinleapyear', 'islower', 'isnan', 'isnull', 'isnumeric',
    'ispm', 'issameday', 'isspace', 'istoday', 'isupper', 'json_array@',
    'json_bool@', 'json_clone@', 'json_count', 'json_get@', 'json_getb',
    'json_getn', 'json_gets$', 'json_has', 'json_isarr', 'json_isbool',
    'json_isnull', 'json_isnum', 'json_isobj', 'json_isstr', 'json_item@',
    'json_itemb', 'json_itemn', 'json_items$', 'json_keys@', 'json_len',
    'json_merge@', 'json_null@', 'json_number@', 'json_object@',
    'json_parse@', 'json_path@', 'json_pathb', 'json_pathn', 'json_paths$',
    'json_pop@', 'json_pretty$', 'json_push@', 'json_pushb@', 'json_pushn@',
    'json_pushnull@', 'json_pushs@', 'json_pushval@', 'json_remove@',
    'json_removeat@', 'json_set@', 'json_setb@', 'json_setn@',
    'json_setnull@', 'json_sets@', 'json_setval@', 'json_string@',
    'json_stringify$', 'json_type', 'json_typename$', 'json_value',
    'json_value$', 'kill', 'lbound', 'lcase$', 'left$', 'len', 'lfill$',
    'librarypath$', 'line$', 'ln', 'loc', 'lof', 'log10', 'log2', 'ltab$',
    'ltrim$', 'max', 'mid$', 'millisecondof', 'millisecondsbetween',
    'millisecondspan', 'min', 'minuteof', 'minutesbetween', 'minutespan',
    'mkdir', 'monthof', 'monthoftheyear', 'monthsbetween', 'monthspan',
    'moviespath$', 'mulstring$', 'musicpath$', 'narr_get', 'narr_set@',
    'ndims', 'now', 'number', 'oct$', 'opentext$', 'os_architecture$',
    'os_build', 'os_check', 'os_major', 'os_minor', 'os_name$',
    'os_platform$', 'os_spmajor', 'os_spminor', 'paramcount', 'paramstr$',
    'parr_get@', 'parr_set@', 'pastetext$', 'path_changeextension$',
    'path_combine$', 'path_getdirectoryname$', 'path_getextension$',
    'path_getfilename$', 'path_getfilenamenoext$', 'path_getfullpath$',
    'path_getpathroot$', 'path_hasextension', 'path_hasvalidfilenamechars',
    'path_hasvalidpathchars', 'path_ispathrooted', 'path_isrelativepath',
    'path_matchespattern', 'pathseparator$', 'pause', 'pdict@', 'pdict_get@',
    'pdict_getdef@', 'pdict_set@', 'pdim@', 'picturespath$', 'pnttonum',
    'pointer@', 'processmessages', 'proper$', 'publicpath$', 'radtodeg',
    'rag@', 'rag_analyze$', 'rag_count', 'rag_doc$', 'rag_error', 'rag_free',
    'rag_funccount', 'rag_functions$', 'rag_rebuild@', 'rag_retrieve$',
    'rag_retrieve_budget$', 'rag_retrieve_json$', 'rag_summary$', 'rag_tags$',
    'randomfilename$', 'randomize', 'regex_find$', 'regex_findall@',
    'regex_findlen', 'regex_findpos', 'regex_group$', 'regex_groupcount',
    'regex_groups@', 'regex_split@', 'replacestr$', 'replacetext$',
    'reverse$', 'rfill$', 'right$', 'ringtonespath$', 'rmdir', 'rnd', 'round',
    'rtab$', 'rtrim$', 'sandboxroot$', 'sarr_get$', 'sarr_set@', 'savetext$',
    'sdict@', 'sdict_get$', 'sdict_getdef$', 'sdict_set@', 'sdim@',
    'secondof', 'secondsbetween', 'secondspan', 'sgn', 'sharedalarmspath$',
    'sharedcamerapath$', 'shareddocumentspath$', 'shareddownloadspath$',
    'sharedmoviespath$', 'sharedmusicpath$', 'sharedpicturespath$',
    'sharedringtonespath$', 'sign', 'sin', 'sinh', 'space$', 'sqr',
    'startsstr', 'startstext', 'str$', 'strchar$', 'strcmp', 'strcmpi',
    'strerror', 'stri$', 'string$', 'strings@', 'strings_add',
    'strings_append', 'strings_beginupdate', 'strings_capacity',
    'strings_casesensitive', 'strings_clear', 'strings_commatext',
    'strings_commatext$', 'strings_count', 'strings_defaultencoding',
    'strings_defaultencoding$', 'strings_delete', 'strings_delimitedtext',
    'strings_delimitedtext$', 'strings_delimiter', 'strings_delimiter$',
    'strings_duplicates', 'strings_duplicates$', 'strings_encoding$',
    'strings_endupdate', 'strings_equals', 'strings_exchange', 'strings_find',
    'strings_free', 'strings_indexof', 'strings_indexofname',
    'strings_insert', 'strings_keynames$', 'strings_linebreak',
    'strings_linebreak$', 'strings_load', 'strings_loadfromfile',
    'strings_loadfromstream', 'strings_move', 'strings_names$',
    'strings_namevalueseparator', 'strings_namevalueseparator$',
    'strings_onchange', 'strings_onchange$', 'strings_onchanging',
    'strings_onchanging$', 'strings_quotechar', 'strings_quotechar$',
    'strings_save', 'strings_savetofile', 'strings_savetostream',
    'strings_sort', 'strings_sorted', 'strings_strictdelimiter',
    'strings_strings', 'strings_strings$', 'strings_text', 'strings_text$',
    'strings_trailinglinebreak', 'strings_valuefromindex',
    'strings_valuefromindex$', 'strings_values', 'strings_values$',
    'strings_writebom', 'strline$', 'strtodate', 'strtodatetime', 'strtotime',
    'stuffstring$', 'swapcase$', 'tan', 'tanh', 'tempfilename$', 'temppath$',
    'time', 'time$', 'timetostr$', 'today', 'tomorrow', 'trim$', 'ubound',
    'ucase$', 'val', 'valcode', 'weekof', 'weekofthemonth', 'weekoftheyear',
    'weeksbetween', 'weeksinayear', 'weeksinyear', 'weekspan', 'word$',
    'wordcount', 'yearof', 'yearsbetween', 'yearspan', 'yesterday'
  );

  BuiltinPackageWords: array[0..180] of String = (
    'at$', 'base64_decode$', 'base64_decodefile', 'base64_encode$',
    'base64_encodefile$', 'base64_error', 'base64_urldecode$',
    'base64_urlencode$', 'base64_valid', 'bg$', 'blink$', 'bold$', 'clreol$',
    'clreos$', 'cls$', 'color$', 'crt_done', 'crt_hideconsole', 'crt_init',
    'crt_showconsole', 'faint$', 'getkey$', 'gzip_compress$',
    'gzip_compressfile', 'gzip_csize', 'gzip_decompress$',
    'gzip_decompressfile', 'gzip_error', 'gzip_ratio', 'gzip_size',
    'hex_decode$', 'hex_encode$', 'hidecursor$', 'home$', 'http_accept',
    'http_accept$', 'http_baseurl', 'http_baseurl$', 'http_basicauth',
    'http_bearerauth', 'http_ca_file$', 'http_clearauth', 'http_clearerror',
    'http_clearproxy', 'http_client@', 'http_contenttype',
    'http_contenttype$', 'http_cookie', 'http_cookie$', 'http_cookieclear',
    'http_cookiecount', 'http_cookieremove', 'http_customauth', 'http_error',
    'http_followredirects', 'http_form@', 'http_formclear', 'http_formfield',
    'http_formfieldcount', 'http_formfile', 'http_formfilecount',
    'http_formfilenamed', 'http_formfiletype', 'http_formfree',
    'http_formurlencoded$', 'http_free', 'http_get$', 'http_header',
    'http_header$', 'http_headerclear', 'http_headercount',
    'http_headerremove', 'http_htmldecode$', 'http_htmlencode$',
    'http_maxredirects', 'http_param', 'http_param$', 'http_paramclear',
    'http_paramcount', 'http_paramremove', 'http_post$', 'http_proxy',
    'http_proxyauth', 'http_reset', 'http_responsetimeout', 'http_status',
    'http_strerror$', 'http_timeout', 'http_urldecode$', 'http_urlencode$',
    'http_useragent', 'http_useragent$', 'http_validatessl',
    'http_verify_peer', 'inkey$', 'inverse$', 'italic$', 'keypressed',
    'movedown$', 'moveleft$', 'moveright$', 'moveup$', 'reset$',
    'restorepos$', 'savepos$', 'showcursor$', 'sqlite_available',
    'sqlite_backup', 'sqlite_begin', 'sqlite_bindjson', 'sqlite_bindnull',
    'sqlite_bindnum', 'sqlite_bindstr', 'sqlite_changes', 'sqlite_clearbind',
    'sqlite_clearerror', 'sqlite_close', 'sqlite_colcount', 'sqlite_colindex',
    'sqlite_colname$', 'sqlite_coltype', 'sqlite_coltypename$',
    'sqlite_columns@', 'sqlite_commit', 'sqlite_eof', 'sqlite_error',
    'sqlite_errormsg$', 'sqlite_escape$', 'sqlite_exec', 'sqlite_fetchall@',
    'sqlite_fetchone@', 'sqlite_finalize', 'sqlite_getn', 'sqlite_getnum',
    'sqlite_gets$', 'sqlite_getstr$', 'sqlite_insertjson', 'sqlite_intrans',
    'sqlite_isblob', 'sqlite_isn', 'sqlite_isnull', 'sqlite_isopen',
    'sqlite_lastid', 'sqlite_open@', 'sqlite_path$', 'sqlite_prepare@',
    'sqlite_query$', 'sqlite_query@', 'sqlite_quote$', 'sqlite_reset',
    'sqlite_rollback', 'sqlite_row@', 'sqlite_scalar', 'sqlite_scalar$',
    'sqlite_step', 'sqlite_strerror$', 'sqlite_tableexists', 'sqlite_tables@',
    'sqlite_totalchanges', 'sqlite_updatejson', 'sqlite_vacuum',
    'sqlite_version$', 'underline$', 'unzip_count', 'unzip_entry$',
    'unzip_extract', 'zip_addfile', 'zip_addstr', 'zip_close', 'zip_compress',
    'zip_count', 'zip_create@', 'zip_entrysize', 'zip_error', 'zip_exists',
    'zip_extract', 'zip_extractall', 'zip_list$', 'zip_open@', 'zip_quick',
    'zip_read$'
  );

  BuiltinGuiWords: array[0..425] of String = (
    'app_processmessages', 'app_quit', 'app_run', 'bevel@', 'bevel_shape',
    'bevel_shape@', 'bevel_style', 'bevel_style@', 'bitbtn@',
    'bitbtn_caption$', 'bitbtn_caption@', 'bitbtn_click@', 'bitbtn_onclick@',
    'bitmap@', 'bitmap_height', 'bitmap_pixel', 'bitmap_width', 'button@',
    'button_caption$', 'button_caption@', 'button_click@', 'button_onclick@',
    'calendar@', 'calendar_date', 'calendar_date@', 'canvas_arc@',
    'canvas_brushcolor@', 'canvas_clear@', 'canvas_ellipse@',
    'canvas_fillrect@', 'canvas_fontcolor@', 'canvas_fontsize@',
    'canvas_line@', 'canvas_lineto@', 'canvas_moveto@', 'canvas_pencolor@',
    'canvas_penwidth@', 'canvas_pie@', 'canvas_polygon@', 'canvas_polyline@',
    'canvas_rectangle@', 'canvas_roundrect@', 'canvas_textheight',
    'canvas_textout@', 'canvas_textwidth', 'checkbox@', 'checkbox_caption$',
    'checkbox_caption@', 'checkbox_checked', 'checkbox_checked@',
    'checkbox_onchange@', 'checkgroup@', 'checkgroup_add@',
    'checkgroup_caption$', 'checkgroup_caption@', 'checkgroup_checked',
    'checkgroup_checked@', 'checkgroup_clear@', 'checkgroup_count',
    'checkgroup_item$', 'checklist_add@', 'checklist_checked',
    'checklist_checked@', 'checklist_count', 'checklist_item$',
    'checklistbox@', 'colorbutton@', 'colorbutton_color',
    'colorbutton_color@', 'colordialog@', 'colordialog_color',
    'colordialog_color@', 'combo_add@', 'combo_clear@', 'combo_count',
    'combo_item$', 'combo_itemindex', 'combo_itemindex@', 'combo_onchange@',
    'combo_text$', 'combobox@', 'control_align', 'control_align@',
    'control_anchors$', 'control_anchors@', 'control_bold', 'control_bold@',
    'control_bounds@', 'control_bringtofront@', 'control_color',
    'control_color@', 'control_cursor', 'control_cursor@', 'control_enabled',
    'control_enabled@', 'control_focused', 'control_fontcolor',
    'control_fontcolor@', 'control_fontname$', 'control_fontname@',
    'control_fontsize', 'control_fontsize@', 'control_free', 'control_get',
    'control_get$', 'control_height', 'control_height@', 'control_hint$',
    'control_hint@', 'control_invalidate@', 'control_italic',
    'control_italic@', 'control_keydown@', 'control_keypress@',
    'control_keyup@', 'control_left', 'control_left@', 'control_maxheight',
    'control_maxheight@', 'control_maxwidth', 'control_maxwidth@',
    'control_minheight', 'control_minheight@', 'control_minwidth',
    'control_minwidth@', 'control_mousedown@', 'control_mousemove@',
    'control_mouseup@', 'control_mousewheel', 'control_move@',
    'control_onkeydown@', 'control_onkeypress@', 'control_onkeyup@',
    'control_onmousedown@', 'control_onmousemove@', 'control_onmouseup@',
    'control_onmousewheel@', 'control_parent@', 'control_sendtoback@',
    'control_set@', 'control_setfocus@', 'control_size@', 'control_spacing',
    'control_spacing@', 'control_taborder', 'control_taborder@',
    'control_tabstop', 'control_tabstop@', 'control_tag', 'control_tag@',
    'control_top', 'control_top@', 'control_underline', 'control_underline@',
    'control_visible', 'control_visible@', 'control_width', 'control_width@',
    'dialog_execute', 'dialog_filename$', 'dialog_filename@',
    'dialog_filter$', 'dialog_filter@', 'dialog_initialdir$',
    'dialog_initialdir@', 'dialog_title$', 'dialog_title@', 'drawgrid@',
    'drawgrid_col', 'drawgrid_colcount', 'drawgrid_colcount@',
    'drawgrid_cursor@', 'drawgrid_drawcell@', 'drawgrid_fixedcols',
    'drawgrid_fixedcols@', 'drawgrid_fixedrows', 'drawgrid_fixedrows@',
    'drawgrid_ondrawcell@', 'drawgrid_row', 'drawgrid_rowcount',
    'drawgrid_rowcount@', 'edit@', 'edit_clear@', 'edit_maxlength',
    'edit_maxlength@', 'edit_onchange@', 'edit_readonly', 'edit_readonly@',
    'edit_selectall@', 'edit_text$', 'edit_text@', 'floatspinedit@',
    'floatspinedit_decimals@', 'floatspinedit_value', 'floatspinedit_value@',
    'fontdialog@', 'fontdialog_fontcolor', 'fontdialog_fontcolor@',
    'fontdialog_fontname$', 'fontdialog_fontname@', 'fontdialog_fontsize',
    'fontdialog_fontsize@', 'form@', 'form_caption$', 'form_caption@',
    'form_close@', 'form_height', 'form_height@', 'form_onclose@',
    'form_onclosequery@', 'form_show@', 'form_visible', 'form_width',
    'form_width@', 'groupbox@', 'groupbox_caption$', 'groupbox_caption@',
    'gui_clearerror', 'gui_error', 'idletimer@', 'image@', 'image_center',
    'image_center@', 'image_empty', 'image_load@', 'image_picheight',
    'image_picwidth', 'image_proportional', 'image_proportional@',
    'image_setbitmap@', 'image_stretch', 'image_stretch@', 'imagelist@',
    'imagelist_addbitmap', 'imagelist_addfile', 'imagelist_attach@',
    'imagelist_clear@', 'imagelist_count', 'inputbox$', 'label@',
    'label_caption$', 'label_caption@', 'list_add@', 'list_clear@',
    'list_count', 'list_item$', 'list_itemindex', 'list_itemindex@',
    'list_onclick@', 'list_selected$', 'listbox@', 'listitem@',
    'listitem_caption$', 'listitem_caption@', 'listitem_subitem$',
    'listitem_subitem@', 'listview@', 'listview_addcolumn@',
    'listview_itemcount', 'mainmenu@', 'maskedit@', 'maskedit_mask$',
    'maskedit_mask@', 'maskedit_text$', 'maskedit_text@', 'memo@',
    'memo_addline@', 'memo_clear@', 'memo_line$', 'memo_linecount',
    'memo_onchange@', 'memo_readonly', 'memo_readonly@', 'memo_text$',
    'memo_text@', 'memo_wordwrap', 'memo_wordwrap@', 'menuitem@',
    'menuitem_caption$', 'menuitem_caption@', 'menuitem_click@',
    'menuitem_onclick@', 'msgbox', 'msgbox_confirm', 'opendialog@',
    'openfile$', 'openpicture$', 'pagecontrol@', 'pagecontrol_pagecount',
    'pagecontrol_pageindex', 'pagecontrol_pageindex@', 'paintbox@',
    'paintbox_onpaint@', 'panel@', 'panel_caption$', 'panel_caption@',
    'popupmenu@', 'popupmenu_attach@', 'progressbar@', 'progressbar_max',
    'progressbar_max@', 'progressbar_min', 'progressbar_min@',
    'progressbar_position', 'progressbar_position@', 'radio_caption$',
    'radio_caption@', 'radio_checked', 'radio_checked@', 'radio_onchange@',
    'radiobutton@', 'radiogroup@', 'radiogroup_add@', 'radiogroup_caption$',
    'radiogroup_caption@', 'radiogroup_clear@', 'radiogroup_count',
    'radiogroup_item$', 'radiogroup_itemindex', 'radiogroup_itemindex@',
    'radiogroup_onchange@', 'savedialog@', 'savefile$', 'savepicture$',
    'scrollbar@', 'scrollbar_max', 'scrollbar_max@', 'scrollbar_min',
    'scrollbar_min@', 'scrollbar_position', 'scrollbar_position@',
    'scrollbox@', 'selectdir$', 'selectdirdialog@', 'shape@',
    'shape_brushcolor', 'shape_brushcolor@', 'shape_kind', 'shape_kind@',
    'shape_pencolor', 'shape_pencolor@', 'speedbutton@',
    'speedbutton_caption$', 'speedbutton_caption@', 'speedbutton_click@',
    'speedbutton_down', 'speedbutton_down@', 'speedbutton_groupindex@',
    'speedbutton_onclick@', 'spinedit@', 'spinedit_max@', 'spinedit_min@',
    'spinedit_onchange@', 'spinedit_value', 'spinedit_value@', 'splitter@',
    'statictext@', 'statictext_caption$', 'statictext_caption@', 'statusbar@',
    'statusbar_text$', 'statusbar_text@', 'stringgrid@', 'stringgrid_cell$',
    'stringgrid_cell@', 'stringgrid_clear@', 'stringgrid_colcount',
    'stringgrid_colcount@', 'stringgrid_fixedrows', 'stringgrid_fixedrows@',
    'stringgrid_rowcount', 'stringgrid_rowcount@', 'tabcontrol@',
    'tabcontrol_add@', 'tabcontrol_clear@', 'tabcontrol_count',
    'tabcontrol_onchange@', 'tabcontrol_tab$', 'tabcontrol_tabindex',
    'tabcontrol_tabindex@', 'tabsheet@', 'tabsheet_caption$',
    'tabsheet_caption@', 'timer@', 'timer_enabled', 'timer_enabled@',
    'timer_interval', 'timer_interval@', 'timer_ontimer@', 'timer_start@',
    'timer_stop@', 'togglebox@', 'togglebox_caption$', 'togglebox_caption@',
    'togglebox_checked', 'togglebox_checked@', 'togglebox_onchange@',
    'toolbar@', 'trackbar@', 'trackbar_max', 'trackbar_max@', 'trackbar_min',
    'trackbar_min@', 'trackbar_onchange@', 'trackbar_position',
    'trackbar_position@', 'trayicon@', 'trayicon_hide@', 'trayicon_hint$',
    'trayicon_hint@', 'trayicon_onclick@', 'trayicon_show@',
    'trayicon_visible', 'treenode@', 'treenode_caption$', 'treenode_caption@',
    'treenode_childcount', 'treeview@', 'treeview_nodecount', 'updown@',
    'updown_max', 'updown_max@', 'updown_min', 'updown_min@',
    'updown_position', 'updown_position@'
  );

var
  { Sorted, case-insensitive indexes over the arrays above, built once at unit
    load. A TStringList.Find is a binary search; the highlighter asks this
    question once per identifier token on every visible line, so a linear scan
    over 1141 names would be felt. }
  FKeywordIndex: TStringList;
  FOperatorIndex: TStringList;
  FLiteralIndex: TStringList;
  FBuiltinIndex: array[TPhosphorTier] of TStringList;

function MakeIndex(const AWords: array of String): TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Duplicates := dupIgnore;
  for I := Low(AWords) to High(AWords) do
    Result.Add(AWords[I]);
  Result.Sorted := True;
end;

function ToArray(const AWords: array of String): TPhosphorWordList;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AWords));
  for I := Low(AWords) to High(AWords) do
    Result[I] := AWords[I];
end;

function IsPhosphorKeyword(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FKeywordIndex.Find(AWord, Dummy);
end;

function IsPhosphorOperatorWord(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FOperatorIndex.Find(AWord, Dummy);
end;

function IsPhosphorLiteralWord(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FLiteralIndex.Find(AWord, Dummy);
end;

function PhosphorBuiltinTier(const AWord: String; out ATier: TPhosphorTier): Boolean;
var
  Tier: TPhosphorTier;
  Dummy: Integer;
begin
  for Tier := Low(TPhosphorTier) to High(TPhosphorTier) do
    if FBuiltinIndex[Tier].Find(AWord, Dummy) then
    begin
      ATier := Tier;
      Exit(True);
    end;
  ATier := ptCore;
  Result := False;
end;

function IsPhosphorBuiltin(const AWord: String): Boolean;
var
  Tier: TPhosphorTier;
begin
  Result := PhosphorBuiltinTier(AWord, Tier);
end;

function PhosphorKeywords: TPhosphorWordList;
begin
  Result := ToArray(KeywordWords);
end;

function PhosphorOperatorWords: TPhosphorWordList;
begin
  Result := ToArray(OperatorWords);
end;

function PhosphorLiteralWords: TPhosphorWordList;
begin
  Result := ToArray(LiteralWords);
end;

function PhosphorBuiltins(ATier: TPhosphorTier): TPhosphorWordList;
begin
  case ATier of
    ptCore: Result := ToArray(BuiltinCoreWords);
    ptPackage: Result := ToArray(BuiltinPackageWords);
  else
    Result := ToArray(BuiltinGuiWords);
  end;
end;

initialization
  FKeywordIndex := MakeIndex(KeywordWords);
  FOperatorIndex := MakeIndex(OperatorWords);
  FLiteralIndex := MakeIndex(LiteralWords);
  FBuiltinIndex[ptCore] := MakeIndex(BuiltinCoreWords);
  FBuiltinIndex[ptPackage] := MakeIndex(BuiltinPackageWords);
  FBuiltinIndex[ptGui] := MakeIndex(BuiltinGuiWords);

finalization
  FreeAndNil(FKeywordIndex);
  FreeAndNil(FOperatorIndex);
  FreeAndNil(FLiteralIndex);
  FreeAndNil(FBuiltinIndex[ptCore]);
  FreeAndNil(FBuiltinIndex[ptPackage]);
  FreeAndNil(FBuiltinIndex[ptGui]);

end.
