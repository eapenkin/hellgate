-module(hg_proto).

-export([get_service_spec/1]).
-export([get_service_spec/2]).

-export_type([service_spec/0]).

%%

-define(VERSION_PREFIX, "/v1").

-type service_spec() :: {Path :: string(), Service :: {module(), atom()}}.

-spec get_service_spec(Name :: atom()) -> service_spec().

get_service_spec(Name) ->
    get_service_spec(Name, #{}).

-spec get_service_spec(Name :: atom(), Opts :: #{namespace => binary()}) -> service_spec().

get_service_spec(eventsink, #{}) ->
    Service = {dmsl_payment_processing_thrift, 'EventSink'},
    {?VERSION_PREFIX ++ "/processing/eventsink", Service};

get_service_spec(party_management, #{}) ->
    Service = {dmsl_payment_processing_thrift, 'PartyManagement'},
    {?VERSION_PREFIX ++ "/processing/partymgmt", Service};

get_service_spec(invoicing, #{}) ->
    Service = {dmsl_payment_processing_thrift, 'Invoicing'},
    {?VERSION_PREFIX ++ "/processing/invoicing", Service};

get_service_spec(invoice_templating, #{}) ->
    Service = {dmsl_payment_processing_thrift, 'InvoiceTemplating'},
    {?VERSION_PREFIX ++ "/processing/invoice_templating", Service};

get_service_spec(processor, #{namespace := Ns}) when is_binary(Ns) ->
    Service = {mg_proto_state_processing_thrift, 'Processor'},
    {?VERSION_PREFIX ++ "/stateproc/" ++ binary_to_list(Ns), Service};

get_service_spec(proxy_host_provider, #{}) ->
    Service = {dmsl_proxy_provider_thrift, 'ProviderProxyHost'},
    {?VERSION_PREFIX ++ "/proxyhost/provider", Service}.
