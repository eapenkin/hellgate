-module(hg_client_customer).
-include_lib("dmsl/include/dmsl_payment_processing_thrift.hrl").

%% API

-export([start     /1]).
-export([start_link/1]).
-export([stop      /1]).

-export([create       /2]).
-export([get          /2]).
-export([delete       /2]).
-export([start_binding/3]).

-export([pull_event/2]).
-export([pull_event/3]).

%% GenServer

-behaviour(gen_server).
-export([init       /1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate  /2]).
-export([code_change/3]).

%% Types

-type id()              :: dmsl_payment_processing_thrift:'CustomerID'().

-type customer()        :: dmsl_payment_processing_thrift:'Customer'().
-type customer_params() :: dmsl_payment_processing_thrift:'CustomerParams'().

-type customer_binding()        :: dmsl_payment_processing_thrift:'CustomerBinding'().
-type customer_binding_params() :: dmsl_payment_processing_thrift:'CustomerBindingParams'().

%% API

-spec start(hg_client_api:t()) ->
    pid().
start(ApiClient) ->
    start(start, ApiClient).

-spec start_link(hg_client_api:t()) ->
    pid().
start_link(ApiClient) ->
    start(start_link, ApiClient).

start(Mode, ApiClient) ->
    {ok, Pid} = gen_server:Mode(?MODULE, ApiClient, []),
    Pid.

-spec stop(pid()) ->
    ok.
stop(Client) ->
    _ = exit(Client, shutdown),
    ok.

%%

-spec create(customer_params(), pid()) ->
    customer() | woody_error:business_error().
create(Params, Client) ->
    map_result_error(gen_server:call(Client, {call, 'Create', [Params]})).

-spec get(id(), pid()) ->
    customer() | woody_error:business_error().
get(ID, Client) ->
    map_result_error(gen_server:call(Client, {call, 'Get', [ID]})).

-spec delete(id(), pid()) ->
    ok | woody_error:business_error().
delete(ID, Client) ->
    map_result_error(gen_server:call(Client, {call, 'Delete', [ID]})).

-spec start_binding(pid(), customer_binding_params(), pid()) ->
    customer_binding().
start_binding(ID, CustomerBindingParams, Client) ->
    map_result_error(gen_server:call(Client, {call, 'StartBinding', [ID, CustomerBindingParams]})).

-define(DEFAULT_NEXT_EVENT_TIMEOUT, 5000).

-spec pull_event(id(), pid()) ->
    tuple() | timeout | woody_error:business_error().

pull_event(CustomerID, Client) ->
    pull_event(CustomerID, ?DEFAULT_NEXT_EVENT_TIMEOUT, Client).

-spec pull_event(id(), timeout(), pid()) ->
    tuple() | timeout | woody_error:business_error().

pull_event(CustomerID, Timeout, Client) ->
    % FIXME: infinity sounds dangerous
    gen_server:call(Client, {pull_event, CustomerID, Timeout}, infinity).

map_result_error({ok, Result}) ->
    Result;
map_result_error({exception, _} = Exception) ->
    Exception;
map_result_error({error, Error}) ->
    error(Error).

%%

-type event() :: dmsl_payment_processing_thrift:'Event'().

-record(st, {
    pollers   :: #{id() => hg_client_event_poller:st(event())},
    client    :: hg_client_api:t()
}).
-type st() :: #st{}.

-type callref() :: {pid(), Tag :: reference()}.

-spec init(hg_client_api:t()) ->
    {ok, st()}.

init(ApiClient) ->
    {ok, #st{pollers = #{}, client = ApiClient}}.

-spec handle_call(term(), callref(), st()) ->
    {reply, term(), st()} | {noreply, st()}.

handle_call({call, Function, Args}, _From, St = #st{client = Client}) ->
    {Result, ClientNext} = hg_client_api:call(customer_management, Function, Args, Client),
    {reply, Result, St#st{client = ClientNext}};

handle_call({pull_event, CustomerID, Timeout}, _From, St = #st{client = Client}) ->
    Poller = get_poller(CustomerID, St),
    {Result, ClientNext, PollerNext} = hg_client_event_poller:poll(1, Timeout, Client, Poller),
    StNext = set_poller(CustomerID, PollerNext, St#st{client = ClientNext}),
    case Result of
        [] ->
            {reply, timeout, StNext};
        [#payproc_Event{payload = Payload}] ->
            {reply, {ok, Payload}, StNext};
        Error ->
            {reply, Error, StNext}
    end;

handle_call(Call, _From, State) ->
    _ = lager:warning("unexpected call received: ~tp", [Call]),
    {noreply, State}.

-spec handle_cast(_, st()) ->
    {noreply, st()}.

handle_cast(Cast, State) ->
    _ = lager:warning("unexpected cast received: ~tp", [Cast]),
    {noreply, State}.

-spec handle_info(_, st()) ->
    {noreply, st()}.

handle_info(Info, State) ->
    _ = lager:warning("unexpected info received: ~tp", [Info]),
    {noreply, State}.

-spec terminate(Reason, st()) ->
    ok when
        Reason :: normal | shutdown | {shutdown, term()} | term().

terminate(_Reason, _State) ->
    ok.

-spec code_change(Vsn | {down, Vsn}, st(), term()) ->
    {error, noimpl} when
        Vsn :: term().

code_change(_OldVsn, _State, _Extra) ->
    {error, noimpl}.

%%

get_poller(ID, #st{pollers = Pollers}) ->
    maps:get(ID, Pollers, construct_poller(ID)).

set_poller(ID, Poller, St = #st{pollers = Pollers}) ->
    St#st{pollers = maps:put(ID, Poller, Pollers)}.

construct_poller(ID) ->
    hg_client_event_poller:new(
        {customer_management, 'GetEvents', [ID]},
        fun (Event) -> Event#payproc_Event.id end
    ).