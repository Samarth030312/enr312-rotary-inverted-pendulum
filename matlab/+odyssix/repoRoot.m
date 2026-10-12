function root = repoRoot()
%REPOROOT  Absolute path of the repository root, derived at run time.
%
%   Never hardcode a machine path. This function locates the repository from
%   the location of this file, so the whole tree can be cloned or copied to any
%   MATLAB workstation and will still work.
%
%   This file lives at  <repo>/matlab/+odyssix/repoRoot.m
%   so the root is two directory levels up from the +odyssix package folder.

    here    = fileparts(mfilename('fullpath'));   % <repo>/matlab/+odyssix
    matdir  = fileparts(here);                    % <repo>/matlab
    root    = fileparts(matdir);                  % <repo>
end
