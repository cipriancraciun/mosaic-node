
-module (mosaic_cluster_processes_wm_v1).


-export ([
		init/1, ping/2,
		allowed_methods/2,
		malformed_request/2,
		content_types_provided/2,
		handle_as_json/2,
		process_post/2]).


-import (mosaic_enforcements, [enforce_ok/1, enforce_ok_1/1]).


-dispatch ({[<<"v1">>, <<"processes">>], {processes, keys}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"keys">>], {processes, keys}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"descriptors">>], {processes, descriptors}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"configurators">>], {processes, configurators}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"configurators">>, <<"register">>], {processes, configurators, register}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"create">>], {processes, create}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"stop">>], {processes, stop}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"call">>], {processes, call}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"cast">>], {processes, cast}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"transcript">>], {processes, transcript}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"ping">>], {ping}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"nodes">>], {nodes}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"nodes">>, <<"self">>, <<"activate">>], {nodes, self, activate}}).
-dispatch ({[<<"v1">>, <<"processes">>, <<"nodes">>, <<"self">>, <<"deactivate">>], {nodes, self, deactivate}}).


-record (state, {target, arguments}).


init (Target) ->
	{ok, #state{target = Target, arguments = none}}.


ping (Request, State = #state{}) ->
    {pong, Request, State}.


allowed_methods (Request, State = #state{target = Target}) ->
	Outcome = case Target of
		{processes, create} ->
			{ok, ['GET', 'POST']};
		_ ->
			{ok, ['GET']}
	end,
	mosaic_webmachine:return_with_outcome (Outcome, Request, State).


malformed_request (Request, OldState = #state{target = Target, arguments = none}) ->
	Outcome = case Target of
		{nodes} ->
			mosaic_webmachine:enforce_get_request ([], Request);
		{nodes, self, Operation} when ((Operation =:= activate) orelse (Operation =:= deactivate)) ->
			mosaic_webmachine:enforce_get_request ([], Request);
		{processes, keys} ->
			mosaic_webmachine:enforce_get_request ([], Request);
		{processes, descriptors} ->
			mosaic_webmachine:enforce_get_request ([], Request);
		{processes, configurators} ->
			mosaic_webmachine:enforce_get_request ([], Request);
		{processes, configurators, register} ->
			case mosaic_webmachine:enforce_get_request (
					[
						{<<"type">>, fun mosaic_generic_coders:decode_string/1},
						{<<"backend_module">>, fun mosaic_generic_coders:decode_atom/1},
						{<<"backend_function">>, fun mosaic_generic_coders:decode_atom/1, configure},
						{<<"context">>, fun mosaic_json_coders:decode_json/1, null},
						{<<"annotation">>, fun mosaic_json_coders:decode_json/1, null}],
					Request) of
				{ok, false, [Type, BackendModule, BackendFunction, Context, Annotation]} ->
					{ok, false, OldState#state{arguments = dict:from_list ([{type, Type}, {backend_module, BackendModule}, {backend_function, BackendModule}, {backend_function, BackendFunction}, {context, Context}, {annotation, Annotation}])}};
				Error = {error, true, _Reason} ->
					Error
			end;
		{processes, create} ->
			case wrq:method (Request) of
				'GET' ->
					case mosaic_webmachine:enforce_get_request (
							[
								{<<"type">>, fun mosaic_generic_coders:decode_string/1},
								{<<"configuration">>, fun mosaic_json_coders:decode_json/1, null},
								{<<"annotation">>, fun mosaic_json_coders:decode_json/1, null},
								{<<"count">>, fun mosaic_generic_coders:decode_integer/1, 1}],
							Request) of
						{ok, false, [Type, Configuration, Annotation, Count]} ->
							if
								(Count > 0), (Count =< 128) ->
									{ok, false, OldState#state{arguments = dict:from_list ([{type, Type}, {configuration, Configuration}, {annotation, Annotation}, {count, Count}])}};
								true ->
									{error, true, {invalid_argument, <<"count">>, {out_of_range, 1, 128}}}
							end;
						Error = {error, true, _Reason} ->
							Error
					end;
				'POST' ->
					case mosaic_webmachine:enforce_post_request ([], json, Request) of
						{ok, false, Json} ->
							{ok, false, OldState#state{arguments = Json}};
						Error = {error, true, _Reason} ->
							Error
					end
			end;
		{processes, stop} ->
			case mosaic_webmachine:enforce_get_request (
					[{<<"key">>, fun mosaic_generic_coders:decode_string/1}],
					Request) of
				{ok, false, [Key]} ->
					{ok, false, OldState#state{arguments = dict:from_list ([{key, Key}])}};
				Error = {error, true, _Reason} ->
					Error
			end;
		{processes, Action} when ((Action =:= call) orelse (Action =:= cast)) ->
			case mosaic_webmachine:enforce_get_request (
					[
						{<<"key">>, fun mosaic_generic_coders:decode_string/1},
						{<<"operation">>, fun mosaic_generic_coders:decode_string/1},
						{<<"inputs">>, fun mosaic_json_coders:decode_json/1, null}],
					Request) of
				{ok, false, [Key, Operation, Inputs]} ->
					{ok, false, OldState#state{arguments = dict:from_list ([{key, Key}, {operation, Operation}, {inputs, Inputs}])}};
				Error = {error, true, _Reason} ->
					Error
			end;
		{processes, transcript} ->
			case mosaic_webmachine:enforce_get_request (
					[{<<"key">>, fun mosaic_generic_coders:decode_string/1, undefined}],
					Request) of
				{ok, false, [Key]} ->
					{ok, false, OldState#state{arguments = dict:from_list ([{key, Key}])}};
				Error = {error, true, _Reason} ->
					Error
			end;
		{ping} ->
			case mosaic_webmachine:enforce_get_request (
					[{<<"count">>, fun mosaic_generic_coders:decode_integer/1, 4}],
					Request) of
				{ok, false, [Count]} ->
					if
						Count =:= 0 ->
							{ok, false, OldState#state{arguments = dict:from_list ([{count, default}])}};
						(Count > 0), (Count =< 128) ->
							{ok, false, OldState#state{arguments = dict:from_list ([{count, Count}])}};
						true ->
							{error, true, {invalid_argument, <<"count">>, {out_of_range, 1, 128}}}
					end;
				Error = {error, true, _Reason} ->
					Error
			end
	end,
	mosaic_webmachine:return_with_outcome (Outcome, Request, OldState).


content_types_provided (Request, State = #state{}) ->
	Outcome = {ok, [{"application/json", handle_as_json}]},
	mosaic_webmachine:return_with_outcome (Outcome, Request, State).


handle_as_json (Request, State = #state{target = Target, arguments = Arguments}) ->
	Outcome = case Target of
		{nodes} ->
			case mosaic_cluster_processes:service_nodes () of
				{ok, Nodes} ->
					{ok, json_struct, [
							{self, enforce_ok_1 (mosaic_generic_coders:encode_atom (erlang:node ()))},
							{nodes, [enforce_ok_1 (mosaic_generic_coders:encode_atom (Node)) || Node <- Nodes]}]};
				Error = {error, _Reason} ->
					Error
			end;
		{nodes, self, activate} ->
			case mosaic_cluster_processes:service_activate () of
				ok ->
					ok;
				Error = {error, _Reason} ->
					Error
			end;
		{nodes, self, deactivate} ->
			case mosaic_cluster_processes:service_deactivate () of
				ok ->
					ok;
				Error = {error, _Reason} ->
					Error
			end;
		{processes, keys} ->
			case mosaic_cluster_processes:list () of
				{ok, Keys, []} ->
					{ok, json_struct, [
							{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || Key <- Keys]}]};
				{ok, Keys, Reasons} ->
					{ok, json_struct, [
							{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || Key <- Keys]},
							{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
				Error = {error, _Reason} ->
					Error
			end;
		{processes, descriptors} ->
			Transform = fun ({Key, Information}) ->
				ProcessType = orddict:fetch (type, Information),
				{ProcessConfigurationEncoding, ProcessConfigurationContent} = orddict:fetch (configuration, Information),
				{ProcessAnnotationEncoding, ProcessAnnotationContent} = case orddict:fetch (annotation, Information) of
					undefined ->
						{json, null};
					ProcessAnnotation_ = {json, _} ->
						ProcessAnnotation_;
					_ ->
						{undefined, undefined}
				end,
				case {ProcessConfigurationEncoding, ProcessAnnotationEncoding} of
					{json, json} ->
						{struct, [
							{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
							{ok, true},
							{type, <<$#, (enforce_ok_1 (mosaic_generic_coders:encode_atom (ProcessType))) / binary>>},
							{configuration, ProcessConfigurationContent},
							{annotation, ProcessAnnotationContent}]};
					{json, _} ->
						{struct, [
							{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
							{ok, false},
							{error, enforce_ok_1 (mosaic_generic_coders:encode_reason (json, invalid_annotation))}]};
					{_, json} ->
						{struct, [
							{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
							{ok, false},
							{error, enforce_ok_1 (mosaic_generic_coders:encode_reason (json, invalid_configuration))}]}
				end
			end,
			case mosaic_cluster_processes:select () of
				{ok, Informations, []} ->
					{ok, json_struct, [
							{descriptors, [Transform (Information) || Information <- Informations]}]};
				{ok, Informations, Reasons} ->
					{ok, json_struct, [
							{descriptors, [Transform (Information) || Information <- Informations]},
							{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
				Error = {error, _Reason} ->
					Error
			end;
		{processes, configurators} ->
			Transform = fun (Information) ->
				Key = orddict:fetch (key, Information),
				ProcessType = orddict:fetch (type, Information),
				ProcessConfigurationEncoding = orddict:fetch (configuration_encoding, Information),
				{ProcessAnnotationEncoding, ProcessAnnotationContent} = case orddict:fetch (annotation, Information) of
					undefined ->
						{json, null};
					ProcessAnnotation_ = {json, _} ->
						ProcessAnnotation_;
					_ ->
						{undefined, undefined}
				end,
				case {ProcessConfigurationEncoding, ProcessAnnotationEncoding} of
					{json, json} ->
						{struct, [
							{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
							{type, <<$#, (enforce_ok_1 (mosaic_generic_coders:encode_atom (ProcessType))) / binary>>},
							{annotation, ProcessAnnotationContent}]};
					{json, _} ->
						null;
					{_, json} ->
						null
				end
			end,
			case mosaic_process_configurator:select () of
				{ok, Informations} ->
					{ok, json_struct, [
							{configurators, [Configurator || Configurator <- [Transform (Information) || Information <- Informations], (Configurator =/= null)]}]};
				Error = {error, _Reason} ->
					Error
			end;
		{processes, configurators, register} ->
			try
				ConfiguratorType = case dict:fetch (type, Arguments) of
					<<$#, ConfiguratorType_ / binary>> ->
						case mosaic_generic_coders:decode_atom (ConfiguratorType_) of
							{ok, ConfiguratorType__} ->
								ConfiguratorType__;
							{error, {inexistent_atom, ConfiguratorType_}} ->
								% !!!!
								erlang:binary_to_atom (ConfiguratorType_, utf8);
							Error1 = {error, _Reason1} ->
								throw (Error1)
						end;
					ConfiguratorType_ ->
						throw ({error, {invalid_type, ConfiguratorType_}})
				end,
				ConfiguratorBackendModule = dict:fetch (backend_module, Arguments),
				ConfiguratorBackendFunction = dict:fetch (backend_function, Arguments),
				ConfiguratorContext = dict:fetch (context, Arguments),
				ConfiguratorAnnotation = dict:fetch (annotation, Arguments),
				case mosaic_process_configurator:register (ConfiguratorType, json, {ConfiguratorBackendModule, ConfiguratorBackendFunction, {json, ConfiguratorContext}}, {json, ConfiguratorAnnotation}) of
					ok ->
						ok;
					Error2 = {error, _Reason2} ->
						Error2
				end
			catch throw : Error = {error, _Reason} -> Error end;
		{processes, create} ->
			try
				ProcessType = case dict:fetch (type, Arguments) of
					<<$#, ProcessType_ / binary>> ->
						case mosaic_generic_coders:decode_atom (ProcessType_) of
							{ok, ProcessType__} ->
								ProcessType__;
							Error1 = {error, _Reason1} ->
								throw (Error1)
						end;
					ProcessType_ ->
						throw ({error, {invalid_type, ProcessType_}})
				end,
				ProcessConfigurationContent = dict:fetch (configuration, Arguments),
				ProcessAnnotationContent = dict:fetch (annotation, Arguments),
				Count = dict:fetch (count, Arguments),
				case mosaic_cluster_processes:define_and_create (ProcessType, json, ProcessConfigurationContent, {json, ProcessAnnotationContent}, Count) of
					{ok, Processes, []} ->
						{ok, json_struct, [
								{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]}]};
					{ok, Processes, Reasons} ->
						{ok, json_struct, [
								{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]},
								{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
					Error2 = {error, _Reason2} ->
						Error2
				end
			catch throw : Error = {error, _Reason} -> Error end;
		{processes, stop} ->
			try
				Key = case dict:fetch (key, Arguments) of
					<<$#, Alias_ / binary>> ->
						case mosaic_process_router:generate_alias (Alias_) of
							{ok, Key_} ->
								Key_;
							{error, _Reason1} ->
								throw ({error, {invalid_alias, Alias_}})
						end;
					Key_ when (byte_size (Key_) =:= 40) ->
						case mosaic_component_coders:decode_component (Key_) of
							{ok, Key__} ->
								Key__;
							{error, _Reason1} ->
								throw ({error, {invalid_component, Key_, invalid_content}})
						end;
					Key_ ->
						throw ({error, {invalid_component, Key_, invalid_length}})
				end,
				case mosaic_process_router:resolve (Key) of
					{ok, Process} ->
						case mosaic_process:stop (Process) of
							ok ->
								ok;
							Error2 = {error, _Reason2} ->
								Error2
						end;
					Error2 = {error, _Reason2} ->
						Error2
				end
			catch throw : Error = {error, _Reason} -> Error end;
		{processes, transcript} ->
			try
				Transform = fun (Record) ->
					case Record of
						{Key, Timestamp_, Data} ->
							{MegaSeconds, Seconds, Microseconds} = Timestamp_,
							Timestamp = (MegaSeconds * 1000000 + Seconds) * 1000000 + Microseconds,
							{struct, [
									{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
									{timestamp, Timestamp},
									{data, Data}]};
						{Timestamp_, Data} ->
							{MegaSeconds, Seconds, Microseconds} = Timestamp_,
							Timestamp = (MegaSeconds * 1000000 + Seconds) * 1000000 + Microseconds,
							{struct, [
									{timestamp, Timestamp},
									{data, Data}]}
					end
				end,
				Key = case dict:fetch (key, Arguments) of
					<<$#, Alias_ / binary>> ->
						case mosaic_process_router:generate_alias (Alias_) of
							{ok, Key_} ->
								Key_;
							{error, _Reason1} ->
								throw ({error, {invalid_alias, Alias_}})
						end;
					Key_ when (byte_size (Key_) =:= 40) ->
						case mosaic_component_coders:decode_component (Key_) of
							{ok, Key__} ->
								Key__;
							{error, _Reason1} ->
								throw ({error, {invalid_component, Key_, invalid_content}})
						end;
					undefined ->
						undefined;
					Key_ ->
						throw ({error, {invalid_component, Key_, invalid_length}})
				end,
				case mosaic_component_transcript:select (Key) of
					{ok, Records} ->
						{ok, json_struct, [
								{records, [Transform (Record) || Record <- Records]}]};
					Error2 = {error, _Reason2} ->
						Error2
				end
			catch throw : Error = {error, _Reason} -> Error end;
		{processes, Action} when ((Action =:= call) orelse (Action =:= cast)) ->
			try
				Key = case dict:fetch (key, Arguments) of
					<<$#, Alias_ / binary>> ->
						case mosaic_process_router:generate_alias (Alias_) of
							{ok, Key_} ->
								Key_;
							{error, _Reason1} ->
								throw ({error, {invalid_alias, Alias_}})
						end;
					Key_ when (byte_size (Key_) =:= 40) ->
						case mosaic_component_coders:decode_component (Key_) of
							{ok, Key__} ->
								Key__;
							{error, _Reason1} ->
								throw ({error, {invalid_component, Key_, invalid_content}})
						end;
					Key_ ->
						throw ({error, {invalid_component, Key_, invalid_length}})
				end,
				Operation = dict:fetch (operation, Arguments),
				Inputs = dict:fetch (inputs, Arguments),
				case Action of
					call ->
						case mosaic_process_router:call (Key, Operation, Inputs, <<>>, undefined) of
							{ok, Outputs, _Data} ->
								case mosaic_json_coders:coerce_json (Outputs) of
									{ok, CoercedOutputs} ->
										{ok, json_struct, [{ok, true}, {outputs, CoercedOutputs}]};
									{error, _Reason2} ->
										{ok, EncodedOutputs} = mosaic_generic_coders:encode_term (json, Outputs),
										{ok, json_struct, [{ok, true}, {outputs, EncodedOutputs}]}
								end;
							{error, Reason2, _Data} ->
								case mosaic_json_coders:coerce_json (Reason2) of
									{ok, CoercedReason2} ->
										{ok, json_struct, [{ok, false}, {error, CoercedReason2}]};
									{error, _Reason2} ->
										{ok, EncodedReason2} = mosaic_generic_coders:encode_term (json, Reason2),
										{ok, json_struct, [{ok, true}, {error, EncodedReason2}]}
								end;
							Error2 = {error, _Reason2} ->
								Error2
						end;
					cast ->
						case mosaic_process_router:cast (Key, Operation, Inputs, <<>>) of
							ok ->
								ok;
							Error2 = {error, _Reason2} ->
								Error2
						end
				end
			catch throw : Error = {error, _Reason} -> Error end;
		{ping} ->
			Count = dict:fetch (count, Arguments),
			case mosaic_cluster_processes:service_ping (Count) of
				{ok, Pongs, Pangs} ->
					{ok, json_struct, [
							{pongs, [
								{struct, [
										{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
										{partition, enforce_ok_1 (mosaic_component_coders:encode_component (<<Partition : 160>>))},
										{node, enforce_ok_1 (mosaic_generic_coders:encode_atom (Node))}]}
								|| {pong, Key, _Vnode, mosaic_cluster_processes, {Partition, Node}} <- Pongs]},
							{pangs, [
								{struct, [
										{key, enforce_ok_1 (mosaic_component_coders:encode_component (Key))},
										{partition, enforce_ok_1 (mosaic_component_coders:encode_component (<<Partition : 160>>))},
										{node, enforce_ok_1 (mosaic_generic_coders:encode_atom (Node))},
										{reason, enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason))}]}
								|| {pang, Key, {Partition, Node}, Reason} <- Pangs]}]};
				Error = {error, _Reason} ->
					Error
			end
	end,
	mosaic_webmachine:respond_with_outcome (Outcome, Request, State).


process_post (Request, State = #state{target = Target, arguments = Json}) ->
	Outcome = case Target of
		{processes, create} ->
			try
				ok = enforce_ok (mosaic_json_coders:validate_json (Json, json_schema (process_specifications))),
				{struct, ProcessSpecifications_} = Json,
				ProcessSpecifications = lists:keysort (6, lists:map (
						fun ({ProcessName, {struct, ProcessSpecification}}) ->
							[
									{<<"annotation">>, ProcessAnnotation},
									{<<"configuration">>, ProcessConfiguration},
									{<<"count">>, Count},
									{<<"delay">>, Delay},
									{<<"order">>, Order},
									{<<"type">>, ProcessType}
							] = lists:keysort (1, ProcessSpecification),
							{ProcessName, ProcessType, ProcessConfiguration, ProcessAnnotation, Count, Order, Delay}
						end,
						ProcessSpecifications_)),
				ProcessOutcomes = lists:map (
						fun ({ProcessName, ProcessType_, ProcessConfigurationContent, ProcessAnnotationContent, Count, _Order, Delay}) ->
							ProcessOutcome = try
								ProcessType = case ProcessType_ of
									<<$#, ProcessType__ / binary>> ->
										case mosaic_generic_coders:decode_atom (ProcessType__) of
											{ok, ProcessType___} ->
												ProcessType___;
											Error1 = {error, _Reason1} ->
												throw (Error1)
										end;
									ProcessType__ ->
										throw ({error, {invalid_type, ProcessType__}})
								end,
								case mosaic_cluster_processes:define_and_create (ProcessType, json, ProcessConfigurationContent, {json, ProcessAnnotationContent}, Count) of
									{ok, Processes, []} ->
										ok = timer:sleep (Delay),
										{struct, [
												{ok, true},
												{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]}]};
									{ok, [], Reasons} ->
										{struct, [
												{ok, true},
												{keys, []},
												{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
									{ok, Processes, Reasons} ->
										ok = timer:sleep (Delay),
										{struct, [
												{ok, true},
												{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]},
												{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
									Error2 = {error, _Reason2} ->
										throw (Error2)
								end
							catch
								throw : {error, Reason3} ->
									{struct, [
											{ok, false},
											{error, enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason3))}]}
							end,
							{ProcessName, ProcessOutcome}
						end,
						ProcessSpecifications),
				{ok, true, json_struct, [{processes, ProcessOutcomes}]}
			catch throw : {error, Reason} -> {error, false, Reason} end
	end,
	mosaic_webmachine:return_with_outcome (Outcome, Request, State).


json_schema (process_specifications) ->
	{is_struct, [{attribute, json_schema (process_specification)}], invalid_process_specifications};
	
json_schema (process_specification) ->
	{is_struct, [{attributes, json_schema (process_specification_attributes)}], invalid_process_specification};
	
json_schema (process_specification_attributes) ->
	[
		{<<"type">>, {is_string, invalid_type}},
		{<<"configuration">>, {is_json, invalid_configuration}},
		{<<"annotation">>, {is_json, invalid_annotation}},
		{<<"count">>, {is_integer, invalid_count}},
		{<<"delay">>, {is_integer, invalid_delay}},
		{<<"order">>, {is_integer, invalid_order}}].
