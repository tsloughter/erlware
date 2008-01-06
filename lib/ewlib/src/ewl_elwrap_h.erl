%%%-------------------------------------------------------------------
%%% File    : ewl_elwrap_h.erl
%%% @doc
%%% add truncation/rotation to the files generated by both the Erlang 
%%%     error_logger and the sasl logger
%%%
%%% <H2>Configuration</H2>
%%% <p>If you start this event handler, you must have an app environment
%%% variable setting like this:</p>
%%%    <code>{err_log_wrap_info, {{err,10000,4},{sasl,10000,4}}}</code>
%%% @end
%%%-------------------------------------------------------------------
-module(ewl_elwrap_h).
-behaviour(gen_event).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include_lib("kernel/include/file.hrl").

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------
-export([
         start_link/0, 
         start_link/1, 
         configuration_spec/1
	]).

%%--------------------------------------------------------------------
%% gen_event callbacks
%%--------------------------------------------------------------------
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
	 terminate/2, code_change/3]).

%%--------------------------------------------------------------------
%% Internal exports
%%--------------------------------------------------------------------
-export([wrap_server_init/1]).

%%--------------------------------------------------------------------
%% Record Definitions
%%--------------------------------------------------------------------
-record(wrap_info, {err_file, err_maxbytes, err_maxfiles,
		    sasl_file, sasl_maxbytes, sasl_maxfiles}).


%%====================================================================
%% Macros
%%====================================================================

-define(ERR_LOG_MGR, error_logger).

%%====================================================================
%% External functions
%%====================================================================
%%--------------------------------------------------------------------
%% @doc Initializes wrapping of (text) error log output.
%% @spec start_link() -> {ok, Pid}
%% @end
%%--------------------------------------------------------------------
start_link() ->

    {ok, Env_tuple} = application:get_env(err_log_wrap_info),
    case Env_tuple of
	{{err, Emaxbytes, Emaxfiles},
	 {sasl, Smaxbytes, Smaxfiles}}
	when Emaxbytes > 100, Emaxbytes < 20000000,
	     Emaxfiles > 0, Emaxfiles < 100,
	     Smaxbytes > 100, Smaxbytes < 20000000,
	     Smaxfiles > 0, Smaxfiles < 100 ->
	    true
    end,

    Efile = error_logger:logfile(filename),
    % Be sure that all config options supported by sasl for the errorlogger are
    % properly dealt with.
    case application:get_env(sasl,sasl_error_logger) of
        undefined ->
            ignore;
        false ->
            ignore;
        to_tty ->
            ignore;
        {ok, {file, Sfile}} ->  
            Wrap_info = #wrap_info{err_file      = Efile,
                                   err_maxbytes  = Emaxbytes,
                                   err_maxfiles  = Emaxfiles,
                                   sasl_file     = Sfile,
                                   sasl_maxbytes = Smaxbytes,
                                   sasl_maxfiles = Smaxfiles},

            {ok, proc_lib:spawn_link(?MODULE, wrap_server_init, [Wrap_info])}
    end.

%%--------------------------------------------------------------------
%% @doc Initializes wrapping of (text) error log output.
%% <pre>
%% Expects:
%%  Options - A list of option tuples for configuration.
%%
%% Types:
%%  Options = [Option]
%%   Option = {sasl_error_logger, Sasl} | {err_log_wrap_info, Value} |
%%            {err_log, ErrFile}
%%    Sasl = undefined | false | to_tty | {file, string()}
%%    WrapSpec = {ErrSpec, SaslSpec}
%%     ErrSpec = {err, Emaxbytes, Emaxfiles},
%%     SaslSpec = {sasl, Smaxbytes, Smaxfiles}}
%%      Emaxbytes = Emaxfiles = Smaxbytes = Smaxfiles = integer()
%%    ErrFile = none | string()
%% </pre>
%% @spec start_link(Options) -> {ok, Pid}
%% @end
%%--------------------------------------------------------------------
start_link(Options) ->
    % allow a flat, unbounded text file for error logs *during test*
    % but turn it off by default in .app.src
    {value, {_, ErrLog}} = lists:keysearch(err_log, 1, Options),
    case ErrLog of
        none ->
            true;
        _other ->
            error_logger:logfile(close),
            error_logger:logfile({open, ErrLog})
    end,

    {value, {_, WrapSpec}} = lists:keysearch(err_log_wrap_info, 1, Options),
    case WrapSpec of
	{{err, Emaxbytes, Emaxfiles},
	 {sasl, Smaxbytes, Smaxfiles}}
	when Emaxbytes > 100, Emaxbytes < 20000000,
	     Emaxfiles > 0, Emaxfiles < 100,
	     Smaxbytes > 100, Smaxbytes < 20000000,
	     Smaxfiles > 0, Smaxfiles < 100 ->
	    true
    end,

    Efile = error_logger:logfile(filename),
    % Be sure that all config options supported by sasl for the errorlogger are
    % properly dealt with.
    {value, {_, Sasl}} = lists:keysearch(sasl_error_logger, 1, Options),
    case Sasl of
        undefined ->
            ignore;
        false ->
            ignore;
        to_tty ->
            ignore;
        {file, Sfile} ->  
            WrapInfo = #wrap_info{err_file      = Efile,
                                  err_maxbytes  = Emaxbytes,
                                  err_maxfiles  = Emaxfiles,
                                  sasl_file     = Sfile,
                                  sasl_maxbytes = Smaxbytes,
                                  sasl_maxfiles = Smaxfiles},

            proc_lib:start_link(?MODULE, wrap_server_init, [WrapInfo])
    end.

%%--------------------------------------------------------------------
%% @doc Returns the configuration keys, required or optional, 
%%      used by G.A.S for configuration of this process.
%% <pre>
%% Conforms to the G.A.S. behaviour.
%% Variables:
%%  Function - The function that the config spec pertains to.
%%
%% Types:
%%  Function = atom()
%%  ConfigurationSpec = [Spec]
%%   Spec = {optional, ConfToken} | {required, ConfToken}
%%    ConfToken = {App, Key} | Key 
%%     App = Key = atom()
%%
%% Configuration:
%%  sasl_error_logger - The location of the sasl log file.
%%  err_log - The location of the error_logger log file.
%%  err_log_tty - bool() to determine if error_logger output is also
%%                directed at the terminal.
%%  err_log_wrap_info - Specs for the wrapping of the sasl and error_logger
%%                      log files.
%%
%% Configuration Types:
%%  err_log_wrap_info = {{err, LogFileBytes, NumFiles}, {sasl, LogFileBytes2, NumFiles2}} 
%% </pre>
%% @spec configuration_spec(Function) -> ConfigurationSpec
%% @end
%%--------------------------------------------------------------------
configuration_spec(start_link) ->
    [{required, {sasl, sasl_error_logger}},
     {required, err_log},
     {optional, err_log_tty},
     {required, err_log_wrap_info}].

%%====================================================================
%% Server functions
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          Other
%% @private
%%--------------------------------------------------------------------
init([Wrap_server]) ->
    {ok, Wrap_server}.

%%--------------------------------------------------------------------
%% Func: handle_event/2
%% Returns: {ok, State}                                |
%%          {swap_handler, Args1, State1, Mod2, Args2} |
%%          remove_handler                              
%%
%% Pull off the event type and send it to the log wrap server.
%% Can't rotate logs in-line as error_logger event mgr is not
%% re-entrant.
%% @private
%%--------------------------------------------------------------------

handle_event(Event, Wrap_server) ->

    case Event of
	Event when tuple(Event) ->
	    Type = element(1, Event),
	    Wrap_server ! {logit, Type};
	_gunk ->
	    true
    end,

    {ok, Wrap_server}.

%%--------------------------------------------------------------------
%% Func: handle_call/2
%% Returns: {ok, Reply, State}                                |
%%          {swap_handler, Reply, Args1, State1, Mod2, Args2} |
%%          {remove_handler, Reply}                            
%% @private
%%--------------------------------------------------------------------
handle_call(_Request, State) ->
    Reply = ok,
    {ok, Reply, State}.

%%--------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {ok, State}                                |
%%          {swap_handler, Args1, State1, Mod2, Args2} |
%%          remove_handler                              
%% @private
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any
%% @private
%%--------------------------------------------------------------------
terminate(Reason, Wrap_server) ->
    Wrap_server ! quit,
    error_logger:info_msg("~p:terminate(~p,~p)~n", 
                          [?MODULE, Reason, Wrap_server]),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% @private
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Func: wrap_server_init/1
%% @doc Sets up a supervised connection between the wrap server
%% and the event_handler that is added to error_logger.
%% @end
%%
%% Expects:
%%  WrapInfo - A record containing information about the properties to be
%%                    observed when wrapping files.
%% 
%% Returns: {ok, Pid} by means of proc_lib:init_ack/1
%% @private
%%--------------------------------------------------------------------
wrap_server_init(WrapInfo) ->
    gen_event:add_sup_handler(?ERR_LOG_MGR, ?MODULE, [self()]),
    proc_lib:init_ack({ok, self()}),
    wrap_server(WrapInfo).

%%--------------------------------------------------------------------
%% Func: wrap_server
%% Purpose: server loop
%%   gets message for each err_log and sasl_log event
%%   if file rotation is needed
%%     rotates files
%%     closes and reopens active logfile
%%
%% Returns: true, but only when the server dies
%%
%% XXX should send mail or such if re-open of logfile fails
%%--------------------------------------------------------------------
wrap_server(W) ->
    receive
	{logit, Type} ->
	    if
		
		%% err_log entry?
		Type == error;
		Type == info_msg;
		Type == info;
		Type == emulator ->
		    case check_log(File = W#wrap_info.err_file,
				   W#wrap_info.err_maxbytes,
				   W#wrap_info.err_maxfiles) of
			rotated ->
			    error_logger:logfile(close),
			    error_logger:logfile({open, File});
			_ ->
			    true
		    end;

		%% sasl_log entry?
		Type == error_report;
		Type == info_report ->
		    case check_log(File = W#wrap_info.sasl_file,
				   W#wrap_info.sasl_maxbytes,
				   W#wrap_info.sasl_maxfiles) of
			rotated ->
			    Sasl_type = get_sasl_error_logger_type(),
			    error_logger:delete_report_handler(sasl_report_file_h),
			    error_logger:add_report_handler(sasl_report_file_h,
							   {File, Sasl_type});
			_ ->
			    true
		    end;

		%% unknown
		true ->
		    true
	    end,		      
	    wrap_server(W);
	quit ->
	    true;
	_what ->
	    true
    end.

%%--------------------------------------------------------------------
%% Func: check_log
%% Purpose: check file size, rotate if needed
%% Returns: rotated     - if files were rotated
%%          not_rotated - if files were not changed
%%--------------------------------------------------------------------

check_log (File, Maxbytes, Maxfiles) ->	
    {ok, Info} = file:read_file_info (File),
    Size = Info#file_info.size,
    if
	Size > Maxbytes ->
	    io:format ("rotating log ~s~n", [File]),

	    %% suppose Maxfiles is 2
	    %% then file.0 -> file.1
	    %% and  file   -> file.0

	    rotate_versions (File, Maxfiles - 1),
	    rotated;
	true ->
	    not_rotated
    end.

%%--------------------------------------------------------------------
%% Func: rotate versions
%% Purpose: rename File -> File.0 .. File.N-1 -> File.N
%% Returns: don't care
%%--------------------------------------------------------------------

rotate_versions (File, N) when is_atom (File) ->
    rotate_versions (atom_to_list (File), N);

rotate_versions (File, 0) when is_list (File) ->
    file:rename (File, File ++ ".0");

rotate_versions (File, N) when is_list (File) ->
    Source = io_lib:format ("~s.~p", [File, N - 1]),
    Destination = io_lib:format ("~s.~p", [File, N]),
    file:rename (Source, Destination),
    rotate_versions (File, N - 1).

%%--------------------------------------------------------------------
%% copied from lib/sasl/src/sasl.erl which did not export it

get_sasl_error_logger_type () ->
    case application:get_env (sasl, errlog_type) of
	{ok, error} -> error;
	{ok, progress} -> progress;
	{ok, all} -> all;
	{ok, Bad} -> exit ({bad_config, {sasl, {errlog_type, Bad}}});
	_ -> all
    end.
















