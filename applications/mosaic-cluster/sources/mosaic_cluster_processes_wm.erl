
-module (mosaic_cluster_processes_wm).


-export ([init/1, allowed_methods/2, content_types_provided/2, malformed_request/2, handle_as_json/2, ping/2]).


-import (mosaic_enforcements, [enforce_ok_1/1]).


-dispatch ({["processes", "nodes"], {nodes}}).
-dispatch ({["processes", "nodes", "self", "activate"], {nodes, self, activate}}).
-dispatch ({["processes", "nodes", "self", "deactivate"], {nodes, self, deactivate}}).
-dispatch ({["processes"], {processes}}).
-dispatch ({["processes", "create"], {processes, create}}).
-dispatch ({["processes", "stop"], {processes, stop}}).
-dispatch ({["processes", "call"], {processes, call}}).
-dispatch ({["processes", "cast"], {processes, cast}}).
-dispatch ({["processes", "ping"], {ping}}).


-record (state, {target, arguments}).


init (Target) ->
	{ok, #state{target = Target, arguments = none}}.

ping(Request, State = #state{}) ->
    {pong, Request, State}.

allowed_methods (Request, State = #state{}) ->
	{['GET'], Request, State}.

content_types_provided (Request, State = #state{}) ->
	{[{"application/json", handle_as_json}], Request, State}.


malformed_request (Request, State = #state{target = Target, arguments = none}) ->
	Outcome = case Target of
		{nodes} ->
			mosaic_webmachine:enforce_request ('GET', [], Request);
		{nodes, self, Operation} when ((Operation =:= activate) orelse (Operation =:= deactivate)) ->
			mosaic_webmachine:enforce_request ('GET', [], Request);
		{processes} ->
			mosaic_webmachine:enforce_request ('GET', [], Request);
		{processes, create} ->
			case mosaic_webmachine:enforce_request ('GET',
					[
						{"type", fun mosaic_generic_coders:decode_atom/1},
						{"arguments", fun mosaic_json_coders:decode_json/1},
						{"count", fun mosaic_generic_coders:decode_integer/1}],
					Request) of
				{ok, false, [Type, Arguments, Count]} ->
					if
						(Count > 0), (Count =< 128) ->
							{ok, false, State#state{arguments = dict:from_list ([{type, Type}, {arguments, Arguments}, {count, Count}])}};
						true ->
							{error, {invalid_argument, "count", {out_of_range, 1, 128}}}
					end;
				Error = {error, _Reason} ->
					Error
			end;
		{processes, stop} ->
			case mosaic_webmachine:enforce_request ('GET', [{"key", fun mosaic_component_coders:decode_component/1}], Request) of
				{ok, false, [Key]} ->
					{ok, false, State#state{arguments = dict:from_list ([{key, Key}])}};
				Error = {error, _Reason} ->
					Error
			end;
		{processes, Action} when ((Action =:= call) orelse (Action =:= cast)) ->
			case mosaic_webmachine:enforce_request ('GET',
					[
						{"key", fun mosaic_component_coders:decode_component/1},
						{"arguments", fun mosaic_json_coders:decode_json/1}],
					Request) of
				{ok, false, [Key, Arguments]} ->
					{ok, false, State#state{arguments = dict:from_list ([{key, Key}, {arguments, Arguments}])}};
				Error = {error, _Reason} ->
					Error
			end;
		{ping} ->
			case mosaic_webmachine:enforce_request ('GET', [{"count", fun mosaic_generic_coders:decode_integer/1}], Request) of
				{ok, false, [Count]} ->
					if
						Count =:= 0 ->
							{ok, false, State#state{arguments = dict:from_list ([{count, default}])}};
						(Count > 0), (Count =< 128) ->
							{ok, false, State#state{arguments = dict:from_list ([{count, Count}])}};
						true ->
							{error, {invalid_argument, "count", {out_of_range, 1, 128}}}
					end;
				Error = {error, _Reason} ->
					Error
			end
	end,
	mosaic_webmachine:return_with_outcome (Outcome, Request, State).


handle_as_json (Request, State = #state{target = Target, arguments = Arguments}) ->
	Outcome = case Target of
		{nodes} ->
			case mosaic_cluster_processes:service_nodes () of
				{ok, Nodes} ->
					{ok, json_struct, [
							{self, mosaic_generic_coders:encode_atom (erlang:node ())},
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
		{processes} ->
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
		{processes, create} ->
			ProcessType = dict:fetch (type, Arguments),
			ProcessArgumentsContent = dict:fetch (arguments, Arguments),
			Count = dict:fetch (count, Arguments),
			case mosaic_cluster_processes:define_and_create (ProcessType, json, ProcessArgumentsContent, Count) of
				{ok, Processes, []} ->
					{ok, json_struct, [
							{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]}]};
				{ok, Processes, Reasons} ->
					{ok, json_struct, [
							{keys, [enforce_ok_1 (mosaic_component_coders:encode_component (Key)) || {Key, _Process} <- Processes]},
							{error, [enforce_ok_1 (mosaic_generic_coders:encode_reason (json, Reason)) || Reason <- Reasons]}]};
				Error = {error, _Reason} ->
					Error
			end;
		{processes, stop} ->
			Key = dict:fetch (key, Arguments),
			case mosaic_cluster_processes:stop (Key) of
				ok ->
					ok;
				Error = {error, _Reason} ->
					Error
			end;
		{processes, Action} when ((Action =:= call) orelse (Action =:= cast)) ->
			Key = dict:fetch (key, Arguments),
			CallArguments = dict:fetch (arguments, Arguments),
			case Action of
				call ->
					case mosaic_process_router:call (Key, CallArguments, <<>>, undefined) of
						{ok, {struct, ReplyAttributes}, _ReplyData} ->
							{ok, json_struct, ReplyAttributes};
						{ok, Reply, _ReplyData} ->
							{error, {invalid_reply, Reply}};
						Error = {error, _Reason} ->
							Error
					end;
				cast ->
					case mosaic_process_router:cast (Key, CallArguments, <<>>) of
						ok ->
							ok;
						Error = {error, _Reason} ->
							Error
					end
			end;
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
