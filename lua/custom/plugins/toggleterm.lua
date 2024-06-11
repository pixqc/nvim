return {
  'akinsho/toggleterm.nvim',
  version = '*',
  config = function()
    require('toggleterm').setup {
      direction = 'vertical',
      size = vim.o.columns * 0.35,
    }
  end,
}
