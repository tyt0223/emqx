%%--------------------------------------------------------------------
%% Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_enhanced_authn_scram_mnesia).

-include("emqx_authn.hrl").
-include_lib("esasl/include/esasl_scram.hrl").
-include_lib("typerefl/include/types.hrl").

-behaviour(hocon_schema).

-export([ structs/0
        , fields/1
        ]).

-export([ create/1
        , update/2
        , authenticate/2
        , destroy/1
        ]).

-export([ add_user/2
        , delete_user/2
        , update_user/3
        , lookup_user/2
        , list_users/1
        ]).

-define(TAB, ?MODULE).

-export([mnesia/1]).

-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

-rlog_shard({?AUTH_SHARD, ?TAB}).

%%------------------------------------------------------------------------------
%% Mnesia bootstrap
%%------------------------------------------------------------------------------

%% @doc Create or replicate tables.
-spec(mnesia(boot | copy) -> ok).
mnesia(boot) ->
    ok = ekka_mnesia:create_table(?TAB, [
                {disc_copies, [node()]},
                {record_name, scram_user_credentail},
                {attributes, record_info(fields, scram_user_credentail)},
                {storage_properties, [{ets, [{read_concurrency, true}]}]}]);

mnesia(copy) ->
    ok = ekka_mnesia:copy_table(?TAB, disc_copies).

%%------------------------------------------------------------------------------
%% Hocon Schema
%%------------------------------------------------------------------------------

structs() -> [config].

fields(config) ->
    [ {name,            fun emqx_authn_schema:authenticator_name/1}
    , {mechanism,       {enum, [scram]}}
    , {server_type,     fun server_type/1}
    , {algorithm,       fun algorithm/1}
    , {iteration_count, fun iteration_count/1}
    ].

server_type(type) -> hoconsc:enum(['built-in-database']);
server_type(default) -> 'built-in-database';
server_type(_) -> undefined.

algorithm(type) -> hoconsc:enum([sha256, sha512]);
algorithm(default) -> sha256;
algorithm(_) -> undefined.

iteration_count(type) -> non_neg_integer();
iteration_count(default) -> 4096;
iteration_count(_) -> undefined.

%%------------------------------------------------------------------------------
%% APIs
%%------------------------------------------------------------------------------

create(#{ algorithm := Algorithm
        , iteration_count := IterationCount
        , '_unique' := Unique
        }) ->
    State = #{user_group => Unique,
              algorithm => Algorithm,
              iteration_count => IterationCount},
    {ok, State}.

update(Config, #{user_group := Unique}) ->
    create(Config#{'_unique' => Unique}).
    
authenticate(#{auth_method := AuthMethod,
               auth_data := AuthData,
               auth_cache := AuthCache}, State) ->
    case ensure_auth_method(AuthMethod, State) of
        true ->
            case AuthCache of
                #{next_step := client_final} ->
                    check_client_final_message(AuthData, AuthCache, State);
                _ ->
                    check_client_first_message(AuthData, AuthCache, State)
            end;
        false ->
            ignore
    end;
authenticate(_Credential, _State) ->
    ignore.

destroy(#{user_group := UserGroup}) ->
    trans(
        fun() ->
            MatchSpec = [{{scram_user_credentail, {UserGroup, '_'}, '_', '_', '_'}, [], ['$_']}],
            ok = lists:foreach(fun(UserCredential) ->
                                  mnesia:delete_object(?TAB, UserCredential, write)
                               end, mnesia:select(?TAB, MatchSpec, write))
        end).

add_user(#{user_id := UserID,
           password := Password}, #{user_group := UserGroup} = State) ->
    trans(
        fun() ->
            case mnesia:read(?TAB, {UserGroup, UserID}, write) of
                [] ->
                    add_user(UserID, Password, State),
                    {ok, #{user_id => UserID}};
                [_] ->
                    {error, already_exist}
            end
        end).

delete_user(UserID, #{user_group := UserGroup}) ->
    trans(
        fun() ->
            case mnesia:read(?TAB, {UserGroup, UserID}, write) of
                [] ->
                    {error, not_found};
                [_] ->
                    mnesia:delete(?TAB, {UserGroup, UserID}, write)
            end
        end).

update_user(UserID, #{password := Password},
            #{user_group := UserGroup} = State) ->
    trans(
        fun() ->
            case mnesia:read(?TAB, {UserGroup, UserID}, write) of
                [] ->
                    {error, not_found};
                [_] ->
                    add_user(UserID, Password, State),
                    {ok, #{user_id => UserID}}
            end
        end).

lookup_user(UserID, #{user_group := UserGroup}) ->
    case mnesia:dirty_read(?TAB, {UserGroup, UserID}) of
        [#scram_user_credentail{user_id = {_, UserID}}] ->
            {ok, #{user_id => UserID}};
        [] ->
            {error, not_found}
    end.

%% TODO: Support Pagination
list_users(#{user_group := UserGroup}) ->
    Users = [#{user_id => UserID} ||
                 #scram_user_credentail{user_id = {UserGroup0, UserID}} <- ets:tab2list(?TAB), UserGroup0 =:= UserGroup],
    {ok, Users}.

%%------------------------------------------------------------------------------
%% Internal functions
%%------------------------------------------------------------------------------

ensure_auth_method('SCRAM-SHA-256', #{algorithm := sha256}) ->
    true;
ensure_auth_method('SCRAM-SHA-512', #{algorithm := sha512}) ->
    true;
ensure_auth_method(_, _) ->
    false.

check_client_first_message(Bin, _Cache, #{iteration_count := IterationCount} = State) ->
    LookupFun = fun(Username) ->
                    lookup_user2(Username, State)
                end,
    case esasl_scram:check_client_first_message(
             Bin,
             #{iteration_count => IterationCount,
               lookup => LookupFun}
         ) of
        {cotinue, ServerFirstMessage, Cache} ->
            {cotinue, ServerFirstMessage, Cache};
        {error, _Reason} ->
            {error, not_authorized}
    end.

check_client_final_message(Bin, Cache, #{algorithm := Alg}) ->
    case esasl_scram:check_client_final_message(
             Bin,
             Cache#{algorithm => Alg}
         ) of
        {ok, ServerFinalMessage} ->
            {ok, ServerFinalMessage};
        {error, _Reason} ->
            {error, not_authorized}
    end.

add_user(UserID, Password, State) ->
    UserCredential = esasl_scram:generate_user_credential(UserID, Password, State),
    mnesia:write(?TAB, UserCredential, write).

lookup_user2(UserID, #{user_group := UserGroup}) ->
    case mnesia:dirty_read(?TAB, {UserGroup, UserID}) of
        [#scram_user_credentail{} = UserCredential] ->
            {ok, UserCredential};
        [] ->
            {error, not_found}
    end.

%% TODO: Move to emqx_authn_utils.erl
trans(Fun) ->
    trans(Fun, []).

trans(Fun, Args) ->
    case ekka_mnesia:transaction(?AUTH_SHARD, Fun, Args) of
        {atomic, Res} -> Res;
        {aborted, Reason} -> {error, Reason}
    end.
