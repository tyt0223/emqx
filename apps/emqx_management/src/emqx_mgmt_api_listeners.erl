%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mgmt_api_listeners).

-behaviour(minirest_api).

-export([api_spec/0]).

-export([ listeners/2
        , listener/2
        , node_listener/2
        , node_listeners/2
        , manage_listeners/2
        , manage_nodes_listeners/2]).

-export([format/1]).

-include_lib("emqx/include/emqx.hrl").

api_spec() ->
    {
        [
            listeners_api(),
            listener_api(),
            nodes_listeners_api(),
            nodes_listener_api(),
            manage_listeners_api(),
            manage_nodes_listeners_api()
        ],
        [listener_schema()]
    }.

listener_schema() ->
    #{
        listener => #{
        type => object,
        properties => #{
            node => #{
                type => string,
                description => <<"Node">>,
                example => node()},
            id => #{
                type => string,
                description => <<"Identifier">>},
            acceptors => #{
                type => integer,
                description => <<"Number of Acceptor process">>},
            max_conn => #{
                type => integer,
                description => <<"Maximum number of allowed connection">>},
            type => #{
                type => string,
                description => <<"Listener type">>},
            listen_on => #{
                type => string,
                description => <<"Listening port">>},
            running => #{
                type => boolean,
                description => <<"Open or close">>},
            auth => #{
                type => boolean,
                description => <<"Has auth">>}}}}.

listeners_api() ->
    Metadata = #{
        get => #{
            description => <<"List listeners in cluster">>,
            responses => #{
                <<"200">> =>
                    emqx_mgmt_util:response_array_schema(<<"List all listeners">>, listener)}}},
    {"/listeners", Metadata, listeners}.

listener_api() ->
    Metadata = #{
        get => #{
            description => <<"List listeners by listener ID">>,
            parameters => [param_path_id()],
            responses => #{
                <<"404">> =>
                    emqx_mgmt_util:response_error_schema(<<"Listener id not found">>, ['BAD_LISTENER_ID']),
                <<"200">> =>
                    emqx_mgmt_util:response_array_schema(<<"List listener info ok">>, listener)}}},
    {"/listeners/:id", Metadata, listener}.

manage_listeners_api() ->
    Metadata = #{
        get => #{
            description => <<"Restart listeners in cluster">>,
            parameters => [
                param_path_id(),
                param_path_operation()],
            responses => #{
                <<"500">> =>
                    emqx_mgmt_util:response_error_schema(<<"Operation  Failed">>, ['INTERNAL_ERROR']),
                <<"404">> =>
                    emqx_mgmt_util:response_error_schema(<<"Listener id not found">>,
                        ['BAD_LISTENER_ID']),
                <<"400">> =>
                    emqx_mgmt_util:response_error_schema(<<"Listener id not found">>,
                        ['BAD_REQUEST']),
                <<"200">> =>
                    emqx_mgmt_util:response_schema(<<"Operation success">>)}}},
    {"/listeners/:id/:operation", Metadata, manage_listeners}.

manage_nodes_listeners_api() ->
    Metadata = #{
        put => #{
            description => <<"Restart listeners in cluster">>,
            parameters => [
                param_path_node(),
                param_path_id(),
                param_path_operation()],
            responses => #{
                <<"500">> =>
                    emqx_mgmt_util:response_error_schema(<<"Operation Failed">>, ['INTERNAL_ERROR']),
                <<"404">> =>
                    emqx_mgmt_util:response_error_schema(<<"Bad node or Listener id not found">>,
                        ['BAD_NODE_NAME','BAD_LISTENER_ID']),
                <<"400">> =>
                    emqx_mgmt_util:response_error_schema(<<"Listener id not found">>,
                        ['BAD_REQUEST']),
                <<"200">> =>
                    emqx_mgmt_util:response_schema(<<"Operation success">>)}}},
    {"/node/:node/listeners/:id/:operation", Metadata, manage_nodes_listeners}.

nodes_listeners_api() ->
    Metadata = #{
        get => #{
            description => <<"Get listener info in one node">>,
            parameters => [param_path_node(), param_path_id()],
            responses => #{
                <<"404">> =>
                    emqx_mgmt_util:response_error_schema(<<"Node name or listener id not found">>,
                        ['BAD_NODE_NAME', 'BAD_LISTENER_ID']),
                <<"200">> =>
                    emqx_mgmt_util:response_schema(<<"Get listener info ok">>, listener)}}},
    {"/nodes/:node/listeners/:id", Metadata, node_listener}.

nodes_listener_api() ->
    Metadata = #{
        get => #{
            description => <<"List listeners in one node">>,
            parameters => [param_path_node()],
            responses => #{
                <<"404">> =>
                    emqx_mgmt_util:response_error_schema(<<"Listener id not found">>),
                <<"200">> =>
                    emqx_mgmt_util:response_schema(<<"Get listener info ok">>, listener)}}},
    {"/nodes/:node/listeners", Metadata, node_listeners}.
%%%==============================================================================================
%% parameters
param_path_node() ->
    #{
        name => node,
        in => path,
        schema => #{type => string},
        required => true,
        example => node()
    }.

param_path_id() ->
    {Example,_} = hd(emqx_mgmt:list_listeners(node())),
    #{
        name => id,
        in => path,
        schema => #{type => string},
        required => true,
        example => Example
    }.

param_path_operation()->
    #{
        name => operation,
        in => path,
        required => true,
        schema => #{
            type => string,
            enum => [start, stop, restart]},
        example => restart
    }.

%%%==============================================================================================
%% api
listeners(get, _Request) ->
    list().

listener(get, Request) ->
    ID = binary_to_atom(cowboy_req:binding(id, Request)),
    get_listeners(#{id => ID}).

node_listeners(get, Request) ->
    Node = binary_to_atom(cowboy_req:binding(node, Request)),
    get_listeners(#{node => Node}).

node_listener(get, Request) ->
    Node = binary_to_atom(cowboy_req:binding(node, Request)),
    ID = binary_to_atom(cowboy_req:binding(id, Request)),
    get_listeners(#{node => Node, id => ID}).

manage_listeners(_, Request) ->
    ID = binary_to_atom(cowboy_req:binding(id, Request)),
    Operation = binary_to_atom(cowboy_req:binding(operation, Request)),
    manage(Operation, #{id => ID}).

manage_nodes_listeners(_, Request) ->
    Node = binary_to_atom(cowboy_req:binding(node, Request)),
    ID = binary_to_atom(cowboy_req:binding(id, Request)),
    Operation = binary_to_atom(cowboy_req:binding(operation, Request)),
    manage(Operation, #{id => ID, node => Node}).

%%%==============================================================================================

%% List listeners in the cluster.
list() ->
    {200, format(emqx_mgmt:list_listeners())}.

get_listeners(Param) ->
    case list_listener(Param) of
        {error, not_found} ->
            ID = maps:get(id, Param),
            Reason = list_to_binary(io_lib:format("Error listener id ~p", [ID])),
            {404, #{code => 'BAD_LISTENER_ID', message => Reason}};
        {error, nodedown} ->
            Node = maps:get(node, Param),
            Reason = list_to_binary(io_lib:format("Node ~p rpc failed", [Node])),
            Response = #{code => 'BAD_NODE_NAME', message => Reason},
            {404, Response};
        [] ->
            ID = maps:get(id, Param),
            Reason = list_to_binary(io_lib:format("Error listener id ~p", [ID])),
            {404, #{code => 'BAD_LISTENER_ID', message => Reason}};
        Data ->
            {200, Data}
    end.

manage(Operation0, Param) ->
    OperationMap = #{start => start_listener, stop => stop_listener, restart => restart_listener},
    Operation = maps:get(Operation0, OperationMap),
    case list_listener(Param) of
        {error, not_found} ->
            ID = maps:get(id, Param),
            Reason = list_to_binary(io_lib:format("Error listener id ~p", [ID])),
            {404, #{code => 'BAD_LISTENER_ID', message => Reason}};
        {error, nodedown} ->
            Node = maps:get(node, Param),
            Reason = list_to_binary(io_lib:format("Node ~p rpc failed", [Node])),
            Response = #{code => 'BAD_NODE_NAME', message => Reason},
            {404, Response};
        [] ->
            ID = maps:get(id, Param),
            Reason = list_to_binary(io_lib:format("Error listener id ~p", [ID])),
            {404, #{code => 'RESOURCE_NOT_FOUND', message => Reason}};
        ListenersOrSingleListener ->
            manage_(Operation, ListenersOrSingleListener)
    end.

manage_(Operation, Listener) when is_map(Listener) ->
    manage_(Operation, [Listener]);
manage_(Operation, Listeners) when is_list(Listeners) ->
    Results = [emqx_mgmt:manage_listener(Operation, Listener) || Listener <- Listeners],
    case lists:filter(fun(Result) -> Result =/= ok end, Results) of
        [] ->
            {200};
        Errors ->
            case lists:filter(fun({error, {already_started, _}}) -> false; (_) -> true end, Results) of
                [] ->
                    ID = maps:get(id, hd(Listeners)),
                    Message = list_to_binary(io_lib:format("Already Started: ~s", [ID])),
                    {400, #{code => 'BAD_REQUEST', message => Message}};
                _ ->
                    case lists:filter(fun({error,not_found}) -> false; (_) -> true end, Results) of
                        [] ->
                            ID = maps:get(id, hd(Listeners)),
                            Message = list_to_binary(io_lib:format("Already Stopped: ~s", [ID])),
                            {400, #{code => 'BAD_REQUEST', message => Message}};
                        _ ->
                            Reason = list_to_binary(io_lib:format("~p", [Errors])),
                            {500, #{code => 'UNKNOW_ERROR', message => Reason}}
                    end
            end
    end.

%%%==============================================================================================
%% util function
list_listener(Params) ->
    format(list_listener_(Params)).

list_listener_(#{node := Node, id := Identifier}) ->
    emqx_mgmt:get_listener(Node, Identifier);
list_listener_(#{id := Identifier}) ->
    emqx_mgmt:list_listeners_by_id(Identifier);
list_listener_(#{node := Node}) ->
    emqx_mgmt:list_listeners(Node);
list_listener_(#{}) ->
    emqx_mgmt:list_listeners().

format(Listeners) when is_list(Listeners) ->
    [format(Listener) || Listener <- Listeners];

format({error, Reason}) ->
    {error, Reason};

format({ID, Conf}) ->
    #{
        id              => ID,
        node            => maps:get(node, Conf),
        acceptors       => maps:get(acceptors, Conf),
        max_conn        => maps:get(max_connections, Conf),
        type            => maps:get(type, Conf),
        listen_on       => list_to_binary(esockd:to_string(maps:get(bind, Conf))),
        running         => trans_running(Conf),
        auth            => maps:get(enable, maps:get(auth, Conf))
    }.
trans_running(Conf) ->
    case maps:get(running, Conf) of
        {error, _} ->
            false;
        Running ->
            Running
    end.
