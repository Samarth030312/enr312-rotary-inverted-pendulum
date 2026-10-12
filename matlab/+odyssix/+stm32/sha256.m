function h = sha256(file)
%SHA256  Lower-case hex SHA-256 of a file (Java, so no toolbox or shell needed).
    fid = fopen(file, 'r'); assert(fid > 0, 'cannot open %s', file);
    c = onCleanup(@() fclose(fid));
    b = fread(fid, Inf, '*uint8');
    md = java.security.MessageDigest.getInstance('SHA-256');
    d = typecast(md.digest(b), 'uint8');
    h = lower(reshape(dec2hex(d, 2)', 1, []));
end
