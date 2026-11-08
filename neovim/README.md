# neovim

Neovim as an IDE for Java, JavaScript and TypeScript, Node, and AWS, built on
[LazyVim](https://www.lazyvim.org), plus GitHub Copilot and Claude Code if
you want them. The Neovim editor itself comes from [`apps/`](../apps), and
Node.js and Java from [`developer/`](../developer/README.md).

| Item | What it does |
| --- | --- |
| `ide` | Kadomo's LazyVim config in `~/.config/nvim`, and what LazyVim needs from Homebrew: `ripgrep`, `fd`, `tree-sitter-cli`, and `lazygit` |
| `copilot` | GitHub Copilot suggestions in Neovim (LazyVim's `ai.copilot` extra) |
| `claude` | Claude Code: the `claude` command (`brew install --cask claude-code`, unless you have it already) and its Neovim integration (LazyVim's `ai.claudecode` extra) |

```sh
./install.sh                     # all three
./install.sh --only ide          # some of them
./install.sh --dry-run
./uninstall.sh                   # undoes what install.sh did
```

In the top-level installer, `ide` is **Developer › Neovim IDE**, and the
other two are in the **AI** category, which is off unless you pick it.

## What's in the config

LazyVim's defaults already cover most of an IDE: lazy.nvim for plugins,
Mason for language servers, blink.cmp for completion, the Snacks picker
(Space Space finds files, Space / searches text), conform.nvim for
formatting, nvim-lint, gitsigns, which-key, Noice, lualine, grug-far
(Space s r: search and replace across files), Trouble, and Treesitter.
[`config/lua/config/lazy.lua`](config/lua/config/lazy.lua) adds these
extras:

| Extra | For |
| --- | --- |
| `lang.java` | Java: jdtls (through nvim-jdtls), debugging, and running tests |
| `lang.typescript` | JavaScript, TypeScript, and Node: vtsls, and debugging Node |
| `linting.eslint`, `formatting.prettier` | ESLint and Prettier, when a project has them set up |
| `lang.json`, `lang.yaml` | JSON and YAML with SchemaStore's schemas (package.json, tsconfig, GitHub Actions, SAM, ...) |
| `lang.docker` | Dockerfiles and Compose files |
| `lang.markdown` | Markdown, rendered in place, with a browser preview |
| `dap.core`, `test.core` | Debugging and test running, for the languages above |
| `coding.mini-surround` | Adding and changing surrounding quotes and brackets |

[`config/lua/plugins/kadomo-aws.lua`](config/lua/plugins/kadomo-aws.lua)
makes the YAML server accept CloudFormation's `!Ref`, `!Sub`, `!GetAtt` and
the other short forms, and runs `cfn-lint` on CloudFormation and SAM
templates (and only those).

The first time Neovim opens, Mason downloads the language servers and tools
these need (jdtls, vtsls, eslint, and so on); `Space c m` shows their
progress. jdtls runs on Java 21 or later, and the JavaScript, JSON, and YAML
servers on Node.js, so pick those under Developer too. Run `:LazyHealth` to
check everything.

The colors follow Kadomo's theme: the theme manager links
`lua/plugins/theme.lua` to the current theme, and `theme-set` changes it.

## Making it yours

Kadomo manages `init.lua`, `lua/config/lazy.lua`, and
`lua/plugins/kadomo-aws.lua`; reinstalling replaces them, keeping a file you
edited as `<name>.bak.<timestamp>`. Everything else is yours, and Kadomo
never touches it:

- `lua/config/options.lua`, `keymaps.lua`, and `autocmds.lua` for settings
- `lua/plugins/<anything>.lua` for plugins of your own, or changes to
  Kadomo's and LazyVim's (see [LazyVim's docs](https://www.lazyvim.org/configuration/plugins))
- `:LazyExtras` to turn more of LazyVim's extras on, such as `lang.terraform`
  for Terraform or `lang.python`; LazyVim keeps that list in `lazyvim.json`

## When a config is already there

The first install sets aside what another config would use, each next to
itself as `<name>.bak.<timestamp>`: `init.lua`, `init.vim`, `lua/`,
`lazy-lock.json`, and `lazyvim.json`. Other files stay where they are, and
Neovim loads them along with Kadomo's config: `plugin/` (Kadomo's Vim and
Neovim settings go there), `colors/`, `after/`, `ftplugin/`. If
`~/.config/nvim` is itself a link (from a dotfiles manager, say), Kadomo
leaves it alone and puts nothing there.

`uninstall.sh` removes Kadomo's files and what Neovim wrote for them, then
puts back what it set aside. Files you added under `lua/` in the meantime are
kept as `lua.bak.<timestamp>`. Neovim's own data stays: the plugins and
language servers it downloaded, in `~/.local/share/nvim`.

## The AI tools

Both are LazyVim extras. The installer writes which are on to
`~/.config/nvim/kadomo-ai.lua`, and `lazy.lua` loads them from there.

**GitHub Copilot** suggests code as you type, in the completion menu. Sign in
once: open `nvim` and run `:Copilot auth`. It needs a Copilot plan (Copilot
Free works) and runs on Node.js.

**Claude Code** runs in a split beside your code and sees what you have open
and selected. Run `claude` in a terminal once to sign in (it needs a Claude
Pro or Max plan, or an Anthropic Console account). Then, in Neovim:

| Keys | |
| --- | --- |
| Space a c | open or close Claude |
| Space a f | focus Claude |
| Space a r / Space a C | resume a past conversation / continue the last one |
| Space a b | add the current file to the conversation |
| Space a s | send the selection (in visual mode) |

Press Space a and wait: which-key lists the rest.

Homebrew doesn't update Claude Code on its own: run `brew upgrade claude-code`.
A Claude Code you installed yourself (with its own installer, say) is used as
it is and never uninstalled.

What Kadomo did is recorded in
`~/Library/Application Support/kadomo/neovim-installed.txt`.
