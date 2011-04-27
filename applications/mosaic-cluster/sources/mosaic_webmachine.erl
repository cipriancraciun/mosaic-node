
-module (mosaic_webmachine).

-export ([start_link/2, enforce_start/0]).
-export ([return_with_outcome/3, respond_with_outcome/3]).
-export ([return_with_content/5, respond_with_content/4]).
-export ([enforce_request/3]).
-export ([parse_existing_atom/1, parse_integer/1, parse_float/1, parse_hex_binary_key/1, parse_json/1]).
-export ([format_atom/1, format_numeric_key/1, format_binary_key/1, format_term/1]).


start_link (QualifiedName = {local, LocalName}, Options)
		when is_atom (LocalName), is_list (Options) ->
	case webmachine_mochiweb:start ([{name, QualifiedName} | Options]) of
		Outcome = {ok, Server} when is_pid (Server) ->
			true = erlang:link (Server),
			Outcome;
		Error = {error, _Reason} ->
			Error
	end.

enforce_start () ->
	QualifiedName = {local, mosaic_webmachine},
	{ok, Dispatches} = dispatches ([mosaic_console_wm, mosaic_cluster_wm, mosaic_executor_wm]),
	ok = case application:get_env (mosaic_cluster, webmachine_listen) of
		undefined ->
			{error, webmachine_unconfigured};
		{ok, {Address, Port}} when is_list (Address), is_number (Port), (Port >= 0), (Port < 65536) ->
			Options = [
					{ip, Address},
					{port, Port},
					{dispatch, Dispatches},
					{error_handler, webmachine_error_handler},
					{enable_perf_logger, false},
					{log_dir, undefined}],
			case mosaic_cluster_sup:start_child_daemon (QualifiedName, mosaic_webmachine, [Options], permanent) of
				{ok, Server} when is_pid (Server) ->
					true = erlang:unlink (Server),
					ok;
				Error = {error, _Reason} ->
					Error
			end
	end,
	ok.


dispatches (Modules)
		when is_list (Modules) ->
	case dispatches (Modules, []) of
		{ok, Dispatches} ->
			{ok, lists:reverse (Dispatches)};
		Error = {error, _Reason} ->
			Error
	end;
	
dispatches (Module)
		when is_atom (Module) ->
	Dispatches = lists:flatten (
			lists:map (
				fun
					({dispatch, [{Path, Arguments}]})
							when is_list (Path) ->
						[{Path, Module, Arguments}];
					({Name, _Value})
							when (Name =/= dispatch) ->
						[]
				end,
				erlang:apply (Module, module_info, [attributes]))),
	{ok, Dispatches}.


dispatches ([], Accumulator) ->
	{ok, Accumulator};
	
dispatches ([Module | Modules], Accumulator) ->
	Outcome = case dispatches (Module) of
		Outcome_ = {ok, []} ->
			Outcome_;
		Outcome_ = {ok, [_]} ->
			Outcome_;
		{ok, Dispatches_ = [_|_]} ->
			{ok, lists:reverse (Dispatches_)}
	end,
	case Outcome of
		{ok, Dispatches} ->
			dispatches (Modules, Dispatches ++ Accumulator);
		Error = {error, _Reason} ->
			Error
	end.


return_with_outcome (Outcome, Request, State) ->
	case Outcome of
		{ok, Return} ->
			{Return, Request, State};
		{ok, Return, NewState} ->
			{Return, Request, NewState};
		{error, Reason} ->
			mosaic_webmachine:return_with_content (true, error, Reason, Request, State)
	end.

respond_with_outcome (Outcome, Request, State) ->
	case Outcome of
		ok ->
			mosaic_webmachine:respond_with_content (json, {struct, [{ok, true}]}, Request, State);
		{ok, json_struct, AttributeTerms} ->
			mosaic_webmachine:respond_with_content (json, {struct, [{ok, true} | AttributeTerms]}, Request, State);
		{error, Reason} ->
			mosaic_webmachine:respond_with_content (error, Reason, Request, State)
	end.


return_with_content (Return, Type, ContentTerm, Request, State) ->
	{ok, ContentType, Content} = encode_content (Type, ContentTerm),
	Response = wrq:set_resp_body (Content, wrq:set_resp_header ("Content-Type", ContentType, Request)),
	{Return, Response, State}.

respond_with_content (Type, ContentTerm, Request, State) ->
	{ok, ContentType, Content} = encode_content (Type, ContentTerm),
	Response = wrq:set_resp_header ("Content-Type", ContentType, Request),
	{Content, Response, State}.


encode_content (json, Content) ->
	{ok, "application/json", format_json (Content)};
	
encode_content (error, Reason) ->
	encode_content (json, {struct, [{ok, false}, {error, format_term (Reason)}]}).


enforce_request (Method, Arguments, Request)
		when is_atom (Method), is_list (Arguments) ->
	case wrq:method (Request) of
		Method ->
			case Arguments of
				[] ->
					{ok, false};
				_ ->
					case parse_arguments (Arguments, Request) of
						{ok, ArgumentNames, ArgumentValues} ->
							case lists:filter (
									fun (Name) -> not lists:member (Name, ArgumentNames) end,
									lists:map (fun ({Name, _}) -> Name end, wrq:req_qs (Request))) of
								[] ->
									{ok, false, ArgumentValues};
								UnexpectedArgumentNames ->
									{error, {unexpected_arguments, UnexpectedArgumentNames}}
							end;
						{error, Reason} ->
							{error, Reason}
					end
			end;
		OtherMethod ->
			{error, {invalid_method, OtherMethod}}
	end.


parse_arguments (Arguments, Request)
		when is_list (Arguments) ->
	case parse_arguments (Arguments, Request, [], []) of
		{ok, Names, Values} ->
			{ok, lists:reverse (Names), lists:reverse (Values)};
		Error = {error, _Reason} ->
			Error
	end.

parse_arguments ([], _Request, Names, Values) ->
	{ok, Names, Values};
	
parse_arguments ([Name | Arguments], Request, Names, Values)
		when is_list (Name) ->
	case wrq:get_qs_value (Name, Request) of
		Value when is_list (Value) ->
			parse_arguments (Arguments, Request, [Name | Names], [Value | Values]);
		undefined ->
			{error, {missing_argument, Name}}
	end;
	
parse_arguments ([{Name, Parser} | Arguments], Request, Names, Values)
		when is_list (Name), is_function (Parser, 1) ->
	case wrq:get_qs_value (Name, Request) of
		ValueString when is_list (ValueString) ->
			case Parser (ValueString) of
				{ok, ValueTerm} ->
					parse_arguments (Arguments, Request, [Name | Names], [ValueTerm | Values]);
				{error, Reason} ->
					{error, {invalid_argument, Name, Reason}}
			end;
		undefined ->
			{error, {missing_argument, Name}}
	end.


parse_existing_atom (String)
		when is_list (String) ->
	try
		{ok, erlang:list_to_existing_atom (String)}
	catch
		error : badarg ->
			{error, {inexistent_atom, String}}
	end.

parse_integer (String)
		when is_list (String) ->
	try
		{ok, erlang:list_to_integer (String)}
	catch
		error : badarg ->
			{error, {invalid_integer, String}}
	end.

parse_float (String)
		when is_list (String) ->
	try
		{ok, erlang:list_to_float (String)}
	catch
		error : badarg ->
			{error, {invalid_float, String}}
	end.

parse_hex_binary_key (String)
		when is_list (String) ->
	try
		Integer = erlang:list_to_integer (String, 16),
		Binary = binary:encode_unsigned (Integer),
		BinarySize = erlang:bit_size (Binary),
		if
			BinarySize =:= 160 ->
				{ok, Binary};
			BinarySize < 160 ->
				{ok, <<0 : (erlang:max (160 - BinarySize)), Binary / binary>>};
			true ->
				{error, {invalid_key_size, BinarySize}}
		end
	catch
		error : _ ->
			{error, {invalid_key, String}}
	end.

parse_json (String)
		when is_list (String) ->
	try
		{ok, mochijson2:decode (String)}
	catch
		error : _ ->
			{error, {invalid_json, String}}
	end.


format_atom (Atom)
		when is_atom (Atom) ->
	erlang:iolist_to_binary (erlang:atom_to_list (Atom)).

format_numeric_key (Key)
		when is_integer (Key), (Key >= 0), (Key < 1461501637330902918203684832716283019655932542976) ->
	KeyHex = string:to_lower (erlang:integer_to_list (Key, 16)),
	KeyHexPadded = lists:duplicate (40 - erlang:length (KeyHex), $0) ++ KeyHex,
	erlang:list_to_binary (KeyHexPadded).

format_binary_key (Key)
		when is_binary (Key), (bit_size (Key) =:= 160) ->
	erlang:iolist_to_binary (lists:flatten ([io_lib:format ("~2.16.0b", [Byte]) || Byte <- erlang:binary_to_list (Key)])).

format_json (Json) ->
	mochijson2:encode (Json).

format_term (Term) ->
	erlang:iolist_to_binary (format_term_ (Term)).

format_term_ (Atom)
		when is_atom (Atom) ->
	[$', erlang:atom_to_list (Atom), $'];
	
format_term_ (Integer)
		when is_integer (Integer) ->
	erlang:integer_to_list (Integer);
	
format_term_ (Float)
		when is_float (Float) ->
	erlang:float_to_list (Float);
	
format_term_ (List)
		when is_list (List) ->
	Ascii = lists:all (fun (Byte) when is_integer (Byte), (Byte >= 32), (Byte =< 127) -> true; (_) -> false end, List),
	if
		Ascii ->
			[$", io_lib:format ("~s", [List]), $"];
		true ->
			[$[, string:join ([format_term_ (Element) || Element <- List], ", "), $]]
	end;
	
format_term_ (Tuple)
		when is_tuple (Tuple) ->
	[${, string:join ([format_term_ (Element) || Element <- erlang:tuple_to_list (Tuple)], ", "), $}];
	
format_term_ (Binary)
		when is_binary (Binary) ->
	["<<16#", [io_lib:format ("~2.16.0b", [Byte]) || Byte <- binary:bin_to_list (Binary)], ":", erlang:integer_to_list (erlang:bit_size (Binary)), ">>"].
