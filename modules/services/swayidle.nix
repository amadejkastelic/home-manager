{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let

  cfg = config.services.swayidle;

in
{
  meta.maintainers = [ maintainers.c0deaddict ];

  options.services.swayidle =
    let

      timeoutModule =
        { ... }:
        {
          options = {
            timeout = mkOption {
              type = types.ints.positive;
              example = 60;
              description = "Timeout in seconds.";
            };

            command = mkOption {
              type = types.str;
              description = "Command to run after timeout seconds of inactivity.";
            };

            resumeCommand = mkOption {
              type = with types; nullOr str;
              default = null;
              description = "Command to run when there is activity again.";
            };
          };
        };

      eventModule =
        { ... }:
        {
          options = {
            event = mkOption {
              type = types.enum [
                "before-sleep"
                "after-resume"
                "lock"
                "unlock"
              ];
              description = "Event name.";
            };

            command = mkOption {
              type = types.str;
              description = "Command to run when event occurs.";
            };
          };
        };

    in
    {
      enable = mkEnableOption "idle manager for Wayland";

      package = lib.mkPackageOption pkgs "swayidle" { };

      timeouts = mkOption {
        type = with types; listOf (submodule timeoutModule);
        default = [ ];
        example = literalExpression ''
          [
            { timeout = 60; command = "${pkgs.swaylock}/bin/swaylock -fF"; }
            { timeout = 90; command = "${pkgs.systemd}/bin/systemctl suspend"; }
          ]
        '';
        description = "List of commands to run after idle timeout.";
      };

      events = mkOption {
        type = with types; listOf (submodule eventModule);
        default = [ ];
        example = literalExpression ''
          [
            { event = "before-sleep"; command = "${pkgs.swaylock}/bin/swaylock -fF"; }
            { event = "lock"; command = "lock"; }
          ]
        '';
        description = "Run command on occurrence of a event.";
      };

      extraArgs = mkOption {
        type = with types; listOf str;
        default = [ "-w" ];
        description = "Extra arguments to pass to swayidle.";
      };

      systemdTarget = mkOption {
        type = types.str;
        default = config.wayland.systemd.target;
        defaultText = literalExpression "config.wayland.systemd.target";
        example = "sway-session.target";
        description = ''
          Systemd target to bind to.
        '';
      };

    };

  config = mkIf cfg.enable {
    assertions = [
      (hm.assertions.assertPlatform "services.swayidle" pkgs platforms.linux)
    ];

    systemd.user.services.swayidle = {
      Unit = {
        Description = "Idle manager for Wayland";
        Documentation = "man:swayidle(1)";
        ConditionEnvironment = "WAYLAND_DISPLAY";
        PartOf = [ cfg.systemdTarget ];
        After = [ cfg.systemdTarget ];
      };

      Service = {
        Type = "simple";
        Restart = "always";
        # swayidle executes commands using "sh -c", so the PATH needs to contain a shell.
        Environment = [ "PATH=${makeBinPath [ pkgs.bash ]}" ];
        ExecStart =
          let
            mkTimeout =
              t:
              [
                "timeout"
                (toString t.timeout)
                t.command
              ]
              ++ optionals (t.resumeCommand != null) [
                "resume"
                t.resumeCommand
              ];

            mkEvent = e: [
              e.event
              e.command
            ];

            args = cfg.extraArgs ++ (concatMap mkTimeout cfg.timeouts) ++ (concatMap mkEvent cfg.events);
          in
          "${getExe cfg.package} ${escapeShellArgs args}";
      };

      Install = {
        WantedBy = [ cfg.systemdTarget ];
      };
    };
  };
}
