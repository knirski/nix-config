{ }:
''
  loki.relabel "journal_drilldown" {
    forward_to = []

    rule {
      source_labels = ["__journal_syslog_identifier"]
      regex         = "(.+)"
      target_label  = "service_name"
    }

    rule {
      source_labels = ["__journal__systemd_unit"]
      regex         = "(.+)"
      target_label  = "service_name"
    }

    rule {
      source_labels = ["__journal_message"]
      regex         = ".*"
      replacement   = "unknown"
      target_label  = "level"
    }

    rule {
      source_labels = ["__journal_message"]
      regex         = ".*"
      replacement   = "unknown"
      target_label  = "detected_level"
    }

    rule {
      source_labels = ["__journal_priority_keyword"]
      regex         = "(.+)"
      target_label  = "level"
    }

    rule {
      source_labels = ["__journal_priority_keyword"]
      regex         = "(.+)"
      target_label  = "detected_level"
    }

    rule {
      source_labels = ["__journal__systemd_unit"]
      regex         = "(.+)"
      target_label  = "unit"
    }
  }

  loki.source.journal "soyo" {
    max_age       = "30m"
    forward_to    = [loki.write.local_loki.receiver]
    relabel_rules = loki.relabel.journal_drilldown.rules
    labels        = {
      job  = "systemd-journal",
      host = "soyo",
    }
  }

  loki.write "local_loki" {
    endpoint {
      url = "http://localhost:3100/loki/api/v1/push"
    }
  }
''
