-module(smelterl_command).

-callback run(Action :: atom(), Opts :: map()) -> integer().
-callback help(Action :: atom()) -> iodata().
-callback actions() -> [atom()].
-callback options_spec(Action :: atom()) -> [map()].
