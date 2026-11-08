-- Kadomo's AWS additions. Kadomo's installer manages this file; put changes
-- in a file of your own in lua/plugins instead.

-- CloudFormation and SAM's short-form functions (!Ref, !Sub, !GetAtt...),
-- which the YAML language server would otherwise call unknown tags.
local cfn_tags = {
  "!And sequence", "!Or sequence", "!Not sequence", "!Equals sequence", "!If sequence",
  "!Condition scalar", "!FindInMap sequence", "!Base64 scalar", "!Base64 mapping",
  "!Cidr scalar", "!Cidr sequence", "!Ref scalar", "!Sub scalar", "!Sub sequence",
  "!GetAtt scalar", "!GetAtt sequence", "!GetAZs scalar", "!GetAZs mapping",
  "!ImportValue scalar", "!ImportValue mapping", "!Select sequence", "!Split sequence",
  "!Join sequence", "!Transform mapping", "!ToJsonString scalar", "!ToJsonString mapping",
  "!Length scalar", "!Length sequence",
}

-- Whether a buffer holds a CloudFormation or SAM template.
local function is_cloudformation(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 200, false)) do
    if line:find("AWSTemplateFormatVersion", 1, true) or line:find("AWS::Serverless", 1, true)
      or line:find("[\"']?Type[\"']?%s*:%s*[\"']?AWS::%w+::") then
      return true
    end
  end
  return false
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = { settings = { yaml = { customTags = cfn_tags } } },
      },
    },
  },

  -- cfn-lint checks CloudFormation and SAM templates, and only those.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "cfn-lint" })
    end,
  },
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      for _, ft in ipairs({ "yaml", "json" }) do
        opts.linters_by_ft[ft] = opts.linters_by_ft[ft] or {}
        table.insert(opts.linters_by_ft[ft], "cfn_lint")
      end
      opts.linters = opts.linters or {}
      opts.linters.cfn_lint = {
        condition = function(ctx)
          return is_cloudformation(ctx.buf)
        end,
      }
    end,
  },
}
