#!/bin/bash
set -e

# ~/.ssh/id_ed25519_djestanet

# ~/.ssh/id_ed25519_djestanet.pub

# .ssh/config
Host djestanet.github.com
    HostName github.com
    # 
    # User djestanet
    User git
    IdentityFile ~/.ssh/id_ed25519_djestanet


Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_djestanet

