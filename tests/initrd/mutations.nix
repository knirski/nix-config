# Named negative fixtures prove that the recovery contract is sensitive to the
# three declarations most likely to be accidentally removed during refactors.
[
  {
    name = "missing-authorized-key";
    mutate = summary: summary // { authorizedKeys = [ ]; };
  }
  {
    name = "missing-runtime-key-mapping";
    mutate = summary: summary // { keyMapping = { }; };
  }
  {
    name = "sshd-before-secret-copy";
    mutate = summary: summary // { sshdAfter = [ "network.target" ]; };
  }
]
