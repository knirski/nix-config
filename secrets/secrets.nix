let
  krzysiek = builtins.readFile ./krzysiek.age.pub;
in
{
  "root-password.age".publicKeys = [ krzysiek ];
  "krzysiek-password.age".publicKeys = [ krzysiek ];
  "restic-password.age".publicKeys = [ krzysiek ];
  "ntfy-token.age".publicKeys = [ krzysiek ];
}
