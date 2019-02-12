-module(rebar_paths_SUITE).
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-compile(export_all).

all() ->
    [clashing_apps,
     check_modules,
     set_paths,
     misloaded_mods
    ].

%%%%%%%%%%%%%%%%%%
%%% TEST SETUP %%%
%%%%%%%%%%%%%%%%%%

init_per_testcase(Case, Config) ->
    BasePaths = code:get_path(),
    %% This test checks that the right module sets get loaded; however, we must
    %% ensure that we do not have clashes with other test suites' loaded modules,
    %% which we cannot track. As such, we have to ensure all module names here are
    %% unique.
    %%
    %% This is done by hand; if you see this test suite failing on its own, you
    %% probably wrote a test suite that clashes!
    Dir = filename:join([?config(priv_dir, Config), atom_to_list(?MODULE),
                         atom_to_list(Case)]),
    InDir = fun(Path) -> filename:join([Dir, Path]) end,
    ADep = fake_app(<<"rp_a">>, <<"1.0.0">>, InDir("_build/default/lib/rp_a/")),
    BDep = fake_app(<<"rp_b">>, <<"1.0.0">>, InDir("_build/default/lib/rp_b/")),
    CDep = fake_app(<<"rp_c">>, <<"1.0.0">>, InDir("_build/default/lib/rp_c/")),
    DDep = fake_app(<<"rp_d">>, <<"1.0.0">>, InDir("_build/default/lib/rp_d/")),
    RelxDep = fake_app(<<"relx">>, <<"1.0.0">>, InDir("_build/default/lib/relx/")),

    APlug = fake_app(<<"rp_a">>, <<"1.0.0">>,
                     InDir("_build/default/plugins/lib/rp_a/")),
    RelxPlug = fake_app(<<"relx">>, <<"1.1.1">>,
                        InDir("_build/default/plugins/lib/relx")),
    EPlug = fake_app(<<"rp_e">>, <<"1.0.0">>,
                     InDir("_build/default/plugins/lib/rp_e/")),

    S0 = rebar_state:new(),
    S1 = rebar_state:all_deps(S0, [ADep, BDep, CDep, DDep, RelxDep]),
    S2 = rebar_state:all_plugin_deps(S1, [APlug, RelxPlug]),
    S3 = rebar_state:code_paths(S2, default, code:get_path()),
    S4 = rebar_state:code_paths(
        S3,
        all_deps,
        [rebar_app_info:ebin_dir(A) || A <- [ADep, BDep, CDep, DDep, RelxDep]]
    ),
    S5 = rebar_state:code_paths(
        S4,
        all_plugin_deps,
        [rebar_app_info:ebin_dir(A) || A <- [APlug, RelxPlug, EPlug]]
    ),
    [{base_paths, BasePaths}, {root_dir, Dir}, {state, S5} | Config].

end_per_testcase(_, Config) ->
    %% this is deeply annoying because we interfere with rebar3's own
    %% path handling!
    rebar_paths:unset_paths([plugins, deps], ?config(state, Config)),
    Config.

fake_app(Name, Vsn, OutDir) ->
    {ok, App} = rebar_app_info:new(Name, Vsn, OutDir),
    compile_fake_appmod(App),
    App.

compile_fake_appmod(App) ->
    OutDir = rebar_app_info:ebin_dir(App),
    Vsn = rebar_app_info:original_vsn(App),
    Name = rebar_app_info:name(App),

    ok = filelib:ensure_dir(filename:join([OutDir, ".touch"])),

    AppFile = [
      "{application,", Name, ", "
      " [{description,  \"some app\"}, "
      "  {vsn, \"", Vsn, "\"}, "
      "  {modules, [",Name,"]}, "
      "  {registered, []}, "
      "  {applications, [stdlib, kernel]} "
      " ]}. "],

    ok = file:write_file(filename:join([OutDir, <<Name/binary, ".app">>]), AppFile),

    Mod = [{attribute, 1, module, binary_to_atom(Name, utf8)},
           {attribute, 2, export, [{f,0}]},
           {function,3,f,0,
            [{clause,3, [], [],
              [{string,3,OutDir}]
            }]}
          ],

    {ok, _, Bin} = compile:forms(Mod),
    ok = file:write_file(filename:join([OutDir, <<Name/binary, ".beam">>]), Bin).

%%%%%%%%%%%%%
%%% TESTS %%%
%%%%%%%%%%%%%

clashing_apps(Config) ->
    Clashes = rebar_paths:clashing_apps([deps, plugins],
                                        ?config(state, Config)),
    ct:pal("Clashes: ~p", [Clashes]),

    ?assertEqual([<<"relx">>, <<"rp_a">>], lists:sort(proplists:get_value(deps, Clashes))),
    ?assertEqual([], proplists:get_value(plugins, Clashes)),
    ok.

set_paths(Config) ->
    State = ?config(state, Config),
    RootDir = filename:split(?config(root_dir, Config)),
    rebar_paths:set_paths([plugins, deps], State),
    PluginPaths = code:get_path(),
    rebar_paths:set_paths([deps, plugins], State),
    DepPaths = code:get_path(),

    ?assertEqual(
       RootDir ++ ["_build", "default", "plugins", "lib", "rp_a", "ebin"],
       find_first_instance("rp_a", PluginPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_b", "ebin"],
       find_first_instance("rp_b", PluginPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_c", "ebin"],
       find_first_instance("rp_c", PluginPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_d", "ebin"],
       find_first_instance("rp_d", PluginPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "plugins", "lib",  "rp_e", "ebin"],
       find_first_instance("rp_e", PluginPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "plugins", "lib", "relx", "ebin"],
       find_first_instance("relx", PluginPaths)
    ),


    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_a", "ebin"],
       find_first_instance("rp_a", DepPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_b", "ebin"],
       find_first_instance("rp_b", DepPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_c", "ebin"],
       find_first_instance("rp_c", DepPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "rp_d", "ebin"],
       find_first_instance("rp_d", DepPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "plugins", "lib", "rp_e", "ebin"],
       find_first_instance("rp_e", DepPaths)
    ),
    ?assertEqual(
       RootDir ++ ["_build", "default", "lib", "relx", "ebin"],
       find_first_instance("relx", DepPaths)
    ),
    ok.

check_modules(Config) ->
    State = ?config(state, Config),
    RootDir = ?config(root_dir, Config)++"/",
    rebar_paths:set_paths([plugins, deps], State),
    ct:pal("code:get_path() -> ~p", [code:get_path()]),

    ?assertEqual(RootDir ++ "_build/default/plugins/lib/rp_a/ebin", rp_a:f()),
    ct:pal("~p", [catch file:list_dir(RootDir ++ "_build/default/lib/")]),
    ct:pal("~p", [catch file:list_dir(RootDir ++ "_build/default/lib/rp_b/")]),
    ct:pal("~p", [catch file:list_dir(RootDir ++ "_build/default/lib/rp_b/ebin")]),
    ct:pal("~p", [catch b:module_info()]),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_b/ebin", rp_b:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_c/ebin", rp_c:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_d/ebin", rp_d:f()),
    ?assertEqual(RootDir ++ "_build/default/plugins/lib/rp_e/ebin", rp_e:f()),
    ?assertEqual(RootDir ++ "_build/default/plugins/lib/relx/ebin", relx:f()),
    ?assertEqual(3, length(relx:module_info(exports))), % can't replace bundled

    rebar_paths:set_paths([deps, plugins], State),
    ct:pal("code:get_path() -> ~p", [code:get_path()]),

    ?assertEqual(RootDir ++ "_build/default/lib/rp_a/ebin", rp_a:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_b/ebin", rp_b:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_c/ebin", rp_c:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_d/ebin", rp_d:f()),
    ?assertEqual(RootDir ++ "_build/default/plugins/lib/rp_e/ebin", rp_e:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/relx/ebin", relx:f()),
    ?assertEqual(3, length(relx:module_info(exports))), % can't replace bundled

    %% once again
    rebar_paths:set_paths([plugins, deps], State),
    ct:pal("code:get_path() -> ~p", [code:get_path()]),

    ?assertEqual(RootDir ++ "_build/default/plugins/lib/rp_a/ebin", rp_a:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_b/ebin", rp_b:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_c/ebin", rp_c:f()),
    ?assertEqual(RootDir ++ "_build/default/lib/rp_d/ebin", rp_d:f()),
    ?assertEqual(RootDir ++ "_build/default/plugins/lib/rp_e/ebin", rp_e:f()),
    ?assertEqual(RootDir ++ "_build/default/plugins/lib/relx/ebin", relx:f()),
    ?assertEqual(3, length(relx:module_info(exports))), % can't replace bundled
    ok.

misloaded_mods(_Config) ->
    Res = rebar_paths:misloaded_modules(
      ["/1/2/3/4",
       "/1/2/4",
       "/2/1/1",
       "/3/4/5"],
      [{a, "/0/1/2/file.beam"},
       {b, "/1/2/3/4/file.beam"},
       {c, "/2/1/file.beam"},
       {f, preloaded},
       {d, "/3/5/7/file.beam"},
       {e, "/3/4/5/file.beam"}]
    ),
    ?assertEqual([a,c,d], Res),
    ok.

%%%%%%%%%%%%%%%
%%% HELPERS %%%
%%%%%%%%%%%%%%%

find_first_instance(Frag, []) ->
    {not_found, Frag};
find_first_instance(Frag, [Path|Rest]) ->
    Frags = filename:split(Path),
    case lists:member(Frag, Frags) of
        true -> Frags;
        false -> find_first_instance(Frag, Rest)
    end.
