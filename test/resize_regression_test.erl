%% @doc Regression tests for ring resize planning and vnode proxy startup.
-module(resize_regression_test).

-include_lib("eunit/include/eunit.hrl").

grow_plan_test_() ->
    [{"grow schedules no transfer to a missing target",
      fun grow_schedules_no_none_target/0},
     {"grow to a ring size that does not divide 2^160 plans without crashing",
      fun grow_to_96_plans/0}].

shrink_proxy_test_() ->
    {setup,
     fun setup_proxies/0,
     fun cleanup_proxies/1,
     fun shrink_starts_proxies_for_future_owners/0}.

grow_schedules_no_none_target() ->
    Orig = riak_core_ring:fresh(64, 'n1@host'),
    Resized = riak_core_ring:fresh(96, 'n1@host'),
    Pending = riak_core_claimant:compute_resize(Orig, Resized),
    Transfers =
        [T
         || {Idx, Owner, '$resize', _, _} <- riak_core_ring:pending_changes(Pending),
            {ok, Ts} <- [riak_core_ring:get_meta({resize, {Idx, Owner}}, Pending)],
            T <- Ts],
    ?assertNotEqual([], Transfers),
    [?assertNotMatch({{_, none}, _, _}, T) || T <- Transfers].

grow_to_96_plans() ->
    Orig = riak_core_ring:fresh(64, 'n1@host'),
    Resized = riak_core_ring:fresh(96, 'n1@host'),
    Pending = riak_core_claimant:compute_resize(Orig, Resized),
    ?assert(riak_core_ring:is_resizing(Pending)).

shrink_starts_proxies_for_future_owners() ->
    Orig = riak_core_ring:fresh(64, 'n1@host'),
    Resized = riak_core_ring:resize(Orig, 32),
    Pending = riak_core_claimant:compute_resize(Orig, Resized),
    application:set_env(riak_core, vnode_modules, [{resize_regression, mock_vnode}]),
    riak_core_ring_handler:handle_event({ring_update, Pending}, undefined),
    Future = riak_core_ring:future_ring(Pending),
    Owners = lists:sort([Idx || {Idx, _} <- riak_core_ring:all_owners(Future)]),
    Running =
        lists:sort([Idx
                    || {{mock_vnode, Idx}, _, _, _}
                           <- supervisor:which_children(riak_core_vnode_proxy_sup)]),
    ?assertEqual(Owners, Running).

setup_proxies() ->
    application:set_env(riak_core, ring_creation_size, 8),
    application:set_env(riak_core, ring_state_dir, "<nostore>"),
    riak_core_ring_events:start_link(),
    riak_core_ring_manager:start_link(test),
    riak_core_vnode_proxy_sup:start_link(),
    ok.

cleanup_proxies(_) ->
    application:unset_env(riak_core, vnode_modules),
    riak_core_test_util:stop_pid(riak_core_vnode_proxy_sup),
    riak_core_test_util:stop_pid(riak_core_ring_manager),
    riak_core_test_util:stop_pid(riak_core_ring_events),
    ok.
