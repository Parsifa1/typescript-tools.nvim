local api = vim.api
local a = require "plenary.async"

local c = require "typescript-tools.protocol.constants"
local plugin_api = require "typescript-tools.api"
local async = require "typescript-tools.async"
local integrations = require "typescript-tools.integrations"

local M = {}

--- @param params table
--- @param callback function
--- @param notify_reply_callback function
function M.handle_command(params, callback, notify_reply_callback)
  local command = params.command
  local command_handler = M[command]

  if command_handler then
    vim.schedule(function()
      command_handler(params)

      notify_reply_callback(command)
      callback(nil, nil)
    end)
  end

  return true, command
end

--- @param params table
M[c.InternalCommands.InvokeAdditionalRename] = function(params)
  local pos = params.arguments[2]

  api.nvim_win_set_cursor(0, { pos.line, pos.offset - 1 })

  -- INFO: wait just a bit to cursor move and then call rename
  vim.defer_fn(function()
    vim.lsp.buf.rename()
  end, 100)
end

M[c.InternalCommands.CallApiFunction] = function(params)
  local api_function = params.arguments[1]

  if api_function then
    plugin_api[api_function]()
  else
    vim.notify(
      "Unknown 'typescript-tools.api." .. api_function .. "' function!",
      vim.log.levels.WARN
    )
  end
end

M[c.InternalCommands.RequestReferences] = function(params)
  vim.lsp.buf_request(0, c.LspMethods.Reference, params.arguments)
end

M[c.InternalCommands.RequestImplementations] = function(params)
  vim.lsp.buf_request(0, c.LspMethods.Implementation, params.arguments)
end

M[c.InternalCommands.InteractiveCodeAction] = function(params)
  local request = unpack(params.arguments)
  a.void(function()
    ---@type string|boolean|nil
    local target_file

    local telescope_err, file = a.wrap(integrations.telescope_picker, 2)()

    if telescope_err then
      target_file = async.ui_input { prompt = "Move to file: " }
    else
      target_file = file
    end

    if target_file == nil or not vim.fn.filereadable(target_file) then
      vim.notify("This refactor require existing file", vim.log.levels.WARN)
      return
    end

    local err, result = async.buf_request_isomorphic(
      false,
      0,
      c.LspMethods.CodeActionResolve,
      vim.tbl_deep_extend(
        "force",
        request,
        { data = { interactiveRefactorArguments = { targetFile = target_file } } }
      )
    )

    if err or not result or not result.edit or (result.edit and vim.tbl_isempty(result.edit)) then
      vim.notify("No refactors available", vim.log.levels.WARN)
      return
    end

    vim.lsp.util.apply_workspace_edit(result.edit, "utf-8")
  end)()
end

return M
