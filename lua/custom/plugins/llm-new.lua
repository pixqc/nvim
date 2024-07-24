return {
  'pixqc/llm.nvim',
  dependencies = { 'nvim-neotest/nvim-nio' },
  config = function()
    local nio = require 'nio'
    local llm_config = {
      -- 'llama-3.1-8b-instant' 'llama-3.1-70b-versatile' 'llama-3.1-405b-reasoning'
      model = 'groq_l3_70b',
      api_key = os.getenv 'GROQ_API_KEY',
      base_url = 'https://api.groq.com/openai/v1/chat/completions',
      system_prompt = 'be brief, get to the point; when outputting code, i dont want explanation, just write the code.',
      timeout_ms = 1000,
      user_prompt = '',
      temperature = 0.7,
      replace = false,
    }

    -- local function get_visual_selection()
    --   local _, srow, scol, _ = unpack(vim.fn.getpos "'<")
    --   local _, erow, ecol, _ = unpack(vim.fn.getpos "'>")
    --   local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
    --
    --   if #lines == 1 then
    --     lines[1] = string.sub(lines[1], scol, ecol)
    --   else
    --     lines[1] = string.sub(lines[1], scol)
    --     lines[#lines] = string.sub(lines[#lines], 1, ecol)
    --   end
    --
    --   return table.concat(lines, '\n')
    -- end
    --
    -- local function get_lines_until_cursor()
    --   local cursor = vim.api.nvim_win_get_cursor(0)
    --   local lines = vim.api.nvim_buf_get_lines(0, 0, cursor[1], false)
    --   lines[#lines] = string.sub(lines[#lines], 1, cursor[2])
    --   return table.concat(lines, '\n')
    -- end
    --
    -- local function get_prompt_text()
    --   if vim.fn.mode() == 'v' or vim.fn.mode() == 'V' then
    --     return get_visual_selection(), true
    --   else
    --     return get_lines_until_cursor(), false
    --   end
    -- end

    local function process_stream(response_text)
      local lines = vim.split(response_text, '\n')
      local has_tokens = false
      local start_time = vim.loop.now()

      for _, line in ipairs(lines) do
        if line:match '^data: ' then
          local json_str = line:sub(6)
          if json_str == '[DONE]' then
            return
          end
          local success, data = pcall(vim.json.decode, json_str)
          if success and data.choices and data.choices[1] and data.choices[1].delta then
            local content = data.choices[1].delta.content
            if content then
              has_tokens = true
              vim.schedule(function()
                vim.cmd 'undojoin'
                local content_lines = vim.split(content, '\n')
                vim.api.nvim_put(content_lines, 'c', true, true)
              end)
            end
          end
        end

        if vim.loop.now() - start_time > llm_config.timeout_ms * 1000 and not has_tokens then
          print 'llm.nvim has timed out!'
          return
        end
      end
    end

    local function prompt(opts)
      local config = vim.tbl_extend('force', llm_config, opts)
      print(config.model)
      local data = {
        messages = {
          { role = 'system', content = config.system_prompt },
          { role = 'user', content = config.user_prompt },
        },
        model = config.model,
        temperature = config.temperature,
        stream = true,
      }
      local headers = {
        'Content-Type: application/json',
        'Authorization: Bearer ' .. config.api_key,
      }
      local args = {
        'curl',
        '-sS',
        '-N',
        '-X',
        'POST',
        '-H',
        headers[1],
        '-H',
        headers[2],
        '-d',
        vim.json.encode(data),
        config.base_url,
      }
      local response = nio.fn.system(args)
      print('Querying ' .. config.model .. '...')
      nio.run(function()
        vim.cmd 'normal! o'
        process_stream(response)
        vim.schedule(function()
          vim.api.nvim_echo({ { '', 'Normal' } }, false, {})
        end)
      end)
    end

    local function set_keymap(mode, key, fn, desc)
      vim.keymap.set(mode, '<leader>l' .. key, fn, { desc = desc })
    end

    local function setup_model_keymaps(key, model, name)
      local base_desc = string.format('LLM %s (Groq %s)', '%s', name)
      set_keymap('n', key, function()
        prompt { model = model, replace = false }
      end, string.format(base_desc, 'Prompt'))
      set_keymap('v', key, function()
        prompt { model = model, replace = false }
      end, string.format(base_desc, 'Prompt') .. ' - Visual')
      set_keymap('v', key:upper(), function()
        prompt { model = model, replace = true }
      end, string.format(base_desc, 'Replace') .. ' - Visual')
    end

    setup_model_keymaps('l', 'llama-3.1-8b-instant', 'Llama3.1-8b')
    setup_model_keymaps('k', 'llama-3.1-70b-versatile', 'Llama3.1-70b')
    setup_model_keymaps('j', 'llama-3.1-405b-reasoning', 'Llama3.1-405b')
  end,
}
