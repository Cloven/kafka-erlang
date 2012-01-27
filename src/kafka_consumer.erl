%% @doc
-module(kafka_consumer).
-author('Knut Nesheim <knutin@gmail.com>').

-behaviour(gen_server).

%% API
-export([start_link/4, get_current_offset/1, fetch/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-record(state, {socket,
                start_offset,
                current_offset,
                max_size = 1048576,
                topic
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Host, Port, Topic, Offset) ->
    gen_server:start_link(?MODULE, [Host, Port, Topic, Offset], []).

get_current_offset(C) ->
    gen_server:call(C, get_current_offset).

fetch(C) ->
    gen_server:call(C, fetch).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Host, Port, Topic, Offset]) ->
    {ok, Socket} = gen_tcp:connect(Host, Port,
                                   [binary, {active, false}, {packet, raw}]),
    {ok, #state{socket = Socket,
                topic = Topic,
                start_offset = Offset,
                current_offset = Offset
               }}.

handle_call(fetch, _From, #state{current_offset = Offset, topic = T} = State) ->
    Req = kafka_protocol:fetch_request(T, Offset, State#state.max_size),
    ok = gen_tcp:send(State#state.socket, Req),

    case gen_tcp:recv(State#state.socket, 6) of
        {ok, <<2:32/integer, 0:16/integer>>} ->
            {reply, {ok, []}, State};
        {ok, <<L:32/integer, 0:16/integer>>} ->
            {ok, Data} = gen_tcp:recv(State#state.socket, L-2),
            {Messages, Size} = kafka_protocol:parse_messages(Data),
            {reply, {ok, Messages}, State#state{current_offset = Offset + Size}};
        {ok, B} ->
            {reply, {error, B}, State}
    end;

handle_call(get_current_offset, _From, State) ->
    {reply, {ok, State#state.current_offset}, State}.


handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(Info, State) ->
    io:format("info: ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

