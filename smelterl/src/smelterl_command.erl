%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_command).
-moduledoc """
Behaviour contract for top-level `smelterl` commands.

Command modules describe which actions they support, the option contract for
each action, and the execution/help callbacks used by the CLI dispatcher.
""".

%=== BEHAVIOUR =================================================================

-doc """
Run one resolved command action with already-parsed options.

Returns the process exit status that `smelterl` should use.
""".
-callback run(Action :: atom(), Opts :: map()) -> integer().

-doc """
Render the help text for one resolved command action.

The returned iodata is written directly to stdout by the CLI dispatcher.
""".
-callback help(Action :: atom()) -> iodata().

-doc """
List the action names handled by this command module.

Single-action command modules return one atom; multi-action modules return one
entry per top-level command they own.
""".
-callback actions() -> [atom()].

-doc """
Return the option specification for one resolved action.

Each option entry uses the `smelterl_cli:option_spec/0` map shape.
""".
-callback options_spec(Action :: atom()) -> [map()].
