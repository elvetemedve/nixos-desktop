{ pkgs, ... }:
{
  programs.helix = {
    enable = true;
    extraPackages = [ pkgs.wl-clipboard ];
    defaultEditor = true;
    settings = {
      keys.insert = {
        S-tab = "unindent";
      };
    };
  };

  programs.neovim = {
    enable = true;
    extraConfig = ''
      set expandtab
      set number
      set shiftwidth=4
      set softtabstop=2
    '';
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

