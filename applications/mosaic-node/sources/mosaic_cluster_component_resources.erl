
-module (mosaic_cluster_component_resources).

-behaviour (gen_server).


-export ([start_supervised/0, start_supervised/1, start_link/2]).
-export ([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).


-import (mosaic_enforcements, [enforce_ok/1, enforce_ok_1/1]).


start_supervised () ->
	start_supervised (defaults).

start_supervised (Configuration) ->
	mosaic_node_sup:start_child_daemon ({local, mosaic_component_resources}, mosaic_cluster_component_resources, Configuration).

start_link (QualifiedName, Configuration) ->
	mosaic_process_tools:start_link (gen_server, mosaic_cluster_component_resources, QualifiedName, Configuration).


-record (state, {qualified_name, table}).


init ({QualifiedName, defaults}) ->
	case mosaic_process_tools:ensure_registered (QualifiedName) of
		ok ->
			Table = ets:new (mosaic_cluster_component_resources, [set, protected, named_table]),
			State = #state{qualified_name = QualifiedName, table = Table},
			{ok, State};
		{error, Reason} ->
			{stop, Reason}
	end.


terminate (_Reason, _State = #state{}) ->
	ok.


code_change (_OldVsn, State = #state{}, _Arguments) ->
	{ok, State}.


handle_call (
			{mosaic_component_resources, acquire, OwnerIdentifier, OwnerProcess, Specifications}, _Sender,
			State = #state{table = Table})
		when is_binary (OwnerIdentifier), (bit_size (OwnerIdentifier) =:= 160), (is_pid (OwnerProcess) orelse is_port (OwnerProcess)) ->
	try
		ok = enforce_ok (mosaic_component_coders:validate_resource_specifications (Specifications)),
		Descriptors = enforce_ok_1 (execute_acquire (OwnerIdentifier, OwnerProcess, Specifications, Table)),
		{reply, {ok, Descriptors}, State}
	catch throw : Error = {error, _Reason} -> {reply, Error, State} end;
	
handle_call (Request, _Sender, State = #state{}) ->
	Error = {error, {invalid_request, Request}},
	{stop, Error, Error, State}.


handle_cast (Request, State = #state{}) ->
	{stop, {error, {invalid_request, Request}}, State}.


handle_info (Message, State = #state{}) ->
	{stop, {error, {invalid_message, Message}}, State}.


execute_acquire (OwnerIdentifier, OwnerProcess, Specifications, Table) ->
	Owner = {OwnerIdentifier, OwnerProcess},
	Cache = lists:foldl (
				fun (Specification, Cache) ->
					enforce_ok_1 (try_acquire (Owner, Specification, Table, Cache))
				end, orddict:new (), Specifications),
	Descriptors = orddict:fold (
				fun (Key, Record = {Key, _Data, Descriptor, _Specification}, Descriptors) ->
					true = ets:insert (Table, Record),
					[Descriptor | Descriptors]
				end, [], Cache),
	{ok, Descriptors}.


try_acquire (Owner, Specification = {Identifier, Type = <<"socket:ipv4:tcp">>, defaults}, _Retry) ->
	try
		Fqdn = enforce_ok_1 (mosaic_generic_coders:application_env_get (node_fqdn, mosaic_node,
				{decode, fun mosaic_generic_coders:decode_string/1}, {error, missing_node_fqdn})),
		Ip = enforce_ok_1 (mosaic_generic_coders:application_env_get (node_ip, mosaic_node,
				{decode, fun mosaic_generic_coders:decode_string/1}, {error, missing_node_ip})),
		Port = crypto:rand_uniform (32769, 49150),
		Key = {Type, Ip, Port},
		Data = {Identifier, Type, Owner, {Ip, Port, Fqdn}},
		Descriptor = {Identifier, [{<<"type">>, Type}, {<<"ip">>, Ip}, {<<"port">>, Port}, {<<"fqdn">>, Fqdn}]},
		{ok, {Key, Data, Descriptor, Specification}}
	catch throw : Error = {error, _Reason} -> Error end;
	
try_acquire (Owner, Specification = {Identifier, Type = <<"socket:ipv4:tcp-service:http">>, defaults}, Retry) ->
	try
		Fqdn = enforce_ok_1 (mosaic_generic_coders:application_env_get (node_fqdn, mosaic_node,
				{decode, fun mosaic_generic_coders:decode_string/1}, {error, missing_node_fqdn})),
		Ip = enforce_ok_1 (mosaic_generic_coders:application_env_get (node_ip, mosaic_node,
				{decode, fun mosaic_generic_coders:decode_string/1}, {error, missing_node_ip})),
		Port = if Retry == 1 -> 31000; true -> crypto:rand_uniform (32769, 49150) end,
		Key = {Type, Ip, Port},
		Data = {Identifier, Type, Owner, {Ip, Port, Fqdn}},
		Descriptor = {Identifier, [{<<"type">>, Type}, {<<"ip">>, Ip}, {<<"port">>, Port}, {<<"fqdn">>, Fqdn}]},
		{ok, {Key, Data, Descriptor, Specification}}
	catch throw : Error = {error, _Reason} -> Error end;
	
try_acquire (_Owner, Specification, _Retry) ->
	throw ({error, {invalid_specification, Specification}}).


try_acquire (Owner, Specification, Table, OldCache) ->
	try_acquire (Owner, Specification, Table, OldCache, 1).

try_acquire (_Owner, _Specification, _Table, _OldCache, Retry) when (Retry >= 10) ->
	{error, unavailable_resources};
	
try_acquire (Owner, Specification, Table, OldCache, Retry) ->
	Record = {Key, _Data, _Descriptor, _Specification} = enforce_ok_1 (try_acquire (Owner, Specification, Retry)),
	case ets:lookup (Table, Key) of
		[] ->
			case orddict:is_key (Key, OldCache) of
				false ->
					NewCache = orddict:store (Key, Record, OldCache),
					{ok, NewCache};
				true ->
					try_acquire (Owner, Specification, Table, OldCache, Retry + 1)
			end;
		_ ->
			try_acquire (Owner, Specification, Table, OldCache, Retry + 1)
	end.
