{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    extraConfig = ''
      set expandtab
      set number
      set shiftwidth=4
      set softtabstop=2
    '';
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      nvim-treesitter.withAllGrammars
      plenary-nvim
      gruvbox-material
      mini-nvim
    ];
  };
}

