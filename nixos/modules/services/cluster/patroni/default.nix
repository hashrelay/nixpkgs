{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.patroni;
  defaultUser = "patroni";
  defaultGroup = "patroni";
  format = pkgs.formats.yaml { };

  configFileName = "patroni-${cfg.scope}-${cfg.name}.yaml";
  configFile = format.generate configFileName cfg.settings;
  configFileCheck = pkgs.runCommand "patroniconfigfile-check" { } ''
    ${cfg.package}/bin/patroni --validate-config ${configFile}
    touch $out
  '';
  patronicli = pkgs.writeShellApplication {
    name = "patronicli";
    runtimeInputs = [ cfg.package ];
    text = ''
      ${lib.strings.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''${k}="$(< ${lib.escapeShellArg v})";export ${k}'') cfg.environmentFiles
      )}
      exec patronictl -c ${configFile} "$@"
    '';
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule
      [
        "services"
        "patroni"
        "raft"
      ]
      ''
        Raft has been deprecated by upstream.
      ''
    )
    (lib.mkRemovedOptionModule
      [
        "services"
        "patroni"
        "raftPort"
      ]
      ''
        Raft has been deprecated by upstream.
      ''
    )
  ];

  options.services.patroni = {

    enable = lib.mkEnableOption "Patroni";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.patroni;
      description = ''
        Patroni package to use.
      '';
    };

    checkConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Check the syntax of the configuration file at compile time";
    };

    postgresqlPackage = lib.mkOption {
      type = lib.types.package;
      example = lib.literalExpression "pkgs.postgresql_14";
      description = ''
        PostgreSQL package to use.
        Plugins can be enabled like this `pkgs.postgresql_14.withPackages (p: [ p.pg_safeupdate p.postgis ])`.
      '';
    };

    postgresqlDataDir = lib.mkOption {
      type = lib.types.path;
      defaultText = lib.literalExpression ''"/var/lib/postgresql/''${config.services.patroni.postgresqlPackage.psqlSchema}"'';
      example = "/var/lib/postgresql/14";
      default = "/var/lib/postgresql/${cfg.postgresqlPackage.psqlSchema}";
      description = ''
        The data directory for PostgreSQL. If left as the default value
        this directory will automatically be created before the PostgreSQL server starts, otherwise
        the sysadmin is responsible for ensuring the directory exists with appropriate ownership
        and permissions.
      '';
    };

    postgresqlPort = lib.mkOption {
      type = lib.types.port;
      default = 5432;
      description = ''
        The port on which PostgreSQL listens.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = defaultUser;
      example = "postgres";
      description = ''
        The user for the service. If left as the default value this user will automatically be created,
        otherwise the sysadmin is responsible for ensuring the user exists.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = defaultGroup;
      example = "postgres";
      description = ''
        The group for the service. If left as the default value this group will automatically be created,
        otherwise the sysadmin is responsible for ensuring the group exists.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/patroni";
      description = ''
        Folder where Patroni data will be written, this is where the pgpass password file will be written.
      '';
    };

    scope = lib.mkOption {
      type = lib.types.str;
      example = "cluster1";
      description = ''
        Cluster name.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      example = "node1";
      description = ''
        The name of the host. Must be unique for the cluster.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "/service";
      description = ''
        Path within the configuration store where Patroni will keep information about the cluster.
      '';
    };

    nodeIp = lib.mkOption {
      type = lib.types.str;
      example = "192.168.1.1";
      description = ''
        IP address of this node.
      '';
    };

    otherNodesIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [
        "192.168.1.2"
        "192.168.1.3"
      ];
      description = ''
        IP addresses of the other nodes.
      '';
    };

    restApiPort = lib.mkOption {
      type = lib.types.port;
      default = 8008;
      description = ''
        The port on Patroni's REST api listens.
      '';
    };

    softwareWatchdog = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This will configure Patroni to use the software watchdog built into the Linux kernel
        as described in the [documentation](https://patroni.readthedocs.io/en/latest/watchdog.html#setting-up-software-watchdog-on-linux).
      '';
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
      description = ''
        The primary patroni configuration. See the [documentation](https://patroni.readthedocs.io/en/latest/SETTINGS.html)
        for possible values.
        Secrets should be passed in by using the `environmentFiles` option.
      '';
    };

    environmentFiles = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          nullOr (oneOf [
            str
            path
            package
          ])
        );
      default = { };
      example = {
        PATRONI_REPLICATION_PASSWORD = "/secret/file";
        PATRONI_SUPERUSER_PASSWORD = "/secret/file";
      };
      description = "Environment variables made available to Patroni as files content, useful for providing secrets from files.";
    };

    initialScript = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''
        pkgs.writeText "init-sql-script" '''
          alter user postgres with password 'myPassword';
        ''';'';

      description = ''
        A file containing SQL statements to execute on first startup.
      '';
    };

    ensureDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Ensures that the specified databases exist.
        This option will never delete existing databases, especially not when the value of this
        option is changed. This means that databases created once through this option or
        otherwise have to be removed manually.
      '';
      example = [
        "gitea"
        "nextcloud"
      ];
    };

    ensureUsers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = ''
                Name of the user to ensure.
              '';
            };

            ensureDBOwnership = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Grants the user ownership to a database with the same name.
                This database must be defined manually in
                [](#opt-services.postgresql.ensureDatabases).
              '';
            };

            ensureClauses = lib.mkOption {
              description = ''
                An attrset of clauses to grant to the user. Under the hood this uses the
                [ALTER USER syntax](https://www.postgresql.org/docs/current/sql-alteruser.html) for each attrName where
                the attrValue is true in the attrSet:
                `ALTER USER user.name WITH attrName`
              '';
              example = lib.literalExpression ''
                {
                  superuser = true;
                  createrole = true;
                  createdb = true;
                }
              '';
              default = { };
              defaultText = lib.literalMD ''
                The default, `null`, means that the user created will have the default permissions assigned by PostgreSQL. Subsequent server starts will not set or unset the clause, so imperative changes are preserved.
              '';
              type = lib.types.submodule {
                options =
                  let
                    defaultText = lib.literalMD ''
                      `null`: do not set. For newly created roles, use PostgreSQL's default. For existing roles, do not touch this clause.
                    '';
                  in
                  {
                    superuser = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, superuser permissions. From the postgres docs:

                        A database superuser bypasses all permission checks,
                        except the right to log in. This is a dangerous privilege
                        and should not be used carelessly; it is best to do most
                        of your work as a role that is not a superuser. To create
                        a new database superuser, use CREATE ROLE name SUPERUSER.
                        You must do this as a role that is already a superuser.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    createrole = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, createrole permissions. From the postgres docs:

                        A role must be explicitly given permission to create more
                        roles (except for superusers, since those bypass all
                        permission checks). To create such a role, use CREATE
                        ROLE name CREATEROLE. A role with CREATEROLE privilege
                        can alter and drop other roles, too, as well as grant or
                        revoke membership in them. However, to create, alter,
                        drop, or change membership of a superuser role, superuser
                        status is required; CREATEROLE is insufficient for that.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    createdb = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, createdb permissions. From the postgres docs:

                        A role must be explicitly given permission to create
                        databases (except for superusers, since those bypass all
                        permission checks). To create such a role, use CREATE
                        ROLE name CREATEDB.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    "inherit" = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user created inherit permissions. From the postgres docs:

                        A role is given permission to inherit the privileges of
                        roles it is a member of, by default. However, to create a
                        role without the permission, use CREATE ROLE name
                        NOINHERIT.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    login = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, login permissions. From the postgres docs:

                        Only roles that have the LOGIN attribute can be used as
                        the initial role name for a database connection. A role
                        with the LOGIN attribute can be considered the same as a
                        “database user”. To create a role with login privilege,
                        use either:

                        CREATE ROLE name LOGIN; CREATE USER name;

                        (CREATE USER is equivalent to CREATE ROLE except that
                        CREATE USER includes LOGIN by default, while CREATE ROLE
                        does not.)

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    replication = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, replication permissions. From the postgres docs:

                        A role must explicitly be given permission to initiate
                        streaming replication (except for superusers, since those
                        bypass all permission checks). A role used for streaming
                        replication must have LOGIN permission as well. To create
                        such a role, use CREATE ROLE name REPLICATION LOGIN.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                    bypassrls = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      description = ''
                        Grants the user, created by the ensureUser attr, replication permissions. From the postgres docs:

                        A role must be explicitly given permission to bypass
                        every row-level security (RLS) policy (except for
                        superusers, since those bypass all permission checks). To
                        create such a role, use CREATE ROLE name BYPASSRLS as a
                        superuser.

                        More information on postgres roles can be found [here](https://www.postgresql.org/docs/current/role-attributes.html)
                      '';
                      default = null;
                      inherit defaultText;
                    };
                  };
              };
            };
          };
        }
      );
      default = [ ];
      description = ''
        Ensures that the specified users exist.
        The PostgreSQL users will be identified using peer authentication. This authenticates the Unix user with the
        same name only, and that without the need for a password.
        This option will never delete existing users or remove DB ownership of databases
        once granted with `ensureDBOwnership = true;`. This means that this must be
        cleaned up manually when changing after changing the config in here.
      '';
      example = lib.literalExpression ''
        [
          {
            name = "nextcloud";
          }
          {
            name = "superuser";
            ensureDBOwnership = true;
          }
        ]
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    system.checks = lib.optional (
      cfg.checkConfig && pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform
    ) configFileCheck;

    services.patroni.settings = {
      scope = cfg.scope;
      name = cfg.name;
      namespace = cfg.namespace;

      restapi = {
        listen = "${cfg.nodeIp}:${toString cfg.restApiPort}";
        connect_address = "${cfg.nodeIp}:${toString cfg.restApiPort}";
      };

      postgresql = {
        listen = "${cfg.nodeIp}:${toString cfg.postgresqlPort}";
        connect_address = "${cfg.nodeIp}:${toString cfg.postgresqlPort}";
        data_dir = cfg.postgresqlDataDir;
        bin_dir = "${cfg.postgresqlPackage}/bin";
        pgpass = "${cfg.dataDir}/pgpass";
      };

      watchdog = lib.mkIf cfg.softwareWatchdog {
        mode = "required";
        device = "/dev/watchdog";
        safety_margin = 5;
      };
    };

    users = {
      users = lib.mkIf (cfg.user == defaultUser) {
        patroni = {
          group = cfg.group;
          isSystemUser = true;
        };
      };
      groups = lib.mkIf (cfg.group == defaultGroup) {
        patroni = { };
      };
    };

    systemd.services = {
      patroni = {
        description = "Runners to orchestrate a high-availability PostgreSQL";

        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        script = ''
          ${lib.concatStringsSep "\n" (
            lib.attrValues (
              lib.mapAttrs (name: path: ''export ${name}="$(< ${lib.escapeShellArg path})"'') cfg.environmentFiles
            )
          )}
          exec ${pkgs.patroni}/bin/patroni ${configFile}
        '';

        path = [
          cfg.postgresqlPackage
        ];
        serviceConfig = lib.mkMerge [
          {
            User = cfg.user;
            Group = cfg.group;
            Type = "simple";
            Restart = "on-failure";
            TimeoutSec = 30;
            ExecReload = "${pkgs.coreutils}/bin/kill -s HUP $MAINPID";
            KillMode = "process";
          }
          (lib.mkIf
            (
              cfg.postgresqlDataDir == "/var/lib/postgresql/${cfg.postgresqlPackage.psqlSchema}"
              && cfg.dataDir == "/var/lib/patroni"
            )
            {
              StateDirectory = "patroni postgresql postgresql/${cfg.postgresqlPackage.psqlSchema}";
              StateDirectoryMode = "0750";
            }
          )
        ];
      };
    };

    boot.kernelModules = lib.mkIf cfg.softwareWatchdog [ "softdog" ];

    services.udev.extraRules = lib.mkIf cfg.softwareWatchdog ''
      KERNEL=="watchdog", OWNER="${cfg.user}", GROUP="${cfg.group}", MODE="0600"
    '';

    environment.systemPackages = [
      pkgs.patroni
      cfg.postgresqlPackage
      patronicli
    ];

    environment.etc."${configFileName}".source = configFile;

    environment.sessionVariables = {
      PATRONICTL_CONFIG_FILE = "/etc/${configFileName}";
    };
  };

  meta.maintainers = [ lib.maintainers.phfroidmont ];
}
