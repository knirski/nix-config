[
  {
    name = "allows-privilege-growth";
    mutate = service: service // { NoNewPrivileges = false; };
  }
  {
    name = "writes-entire-root";
    mutate = service: service // { ReadWritePaths = [ "/" ]; };
  }
  {
    name = "unbounded-start";
    mutate = service: service // { TimeoutStartSec = "infinity"; };
  }
  {
    name = "restart-loop";
    mutate = service: service // { Restart = "always"; };
  }
]
