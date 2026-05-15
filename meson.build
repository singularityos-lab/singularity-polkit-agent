project('singularity-polkit-agent', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 0.59.0',
)

# Dependencies
gtk4_dep = dependency('gtk4')
polkit_gobject_dep = dependency('polkit-gobject-1')
polkit_agent_dep = dependency('polkit-agent-1')

# libsingularity dependency
if meson.is_subproject()
  libsingularity_subproj = subproject('libsingularity')
  libsingularity_dep = libsingularity_subproj.get_variable('libsingularity_dep')
else
  libsingularity_dep = dependency('singularity-1.0')
endif

agent_sources = files(
  'src/main.vala',
  'src/agent.vala',
)

helper_sources = files(
  'src/helper_main.vala',
  'src/auth_dialog.vala',
)

executable('singularity-polkit-agent',
  sources: agent_sources,
  vala_args: [
    '--pkg=polkit-agent-1',
    '--pkg=polkit-gobject-1',
    '--pkg=posix',
  ],
  c_args: [
    '-DPOLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE',
    '-DGETTEXT_PACKAGE="singularity-polkit-agent"',
  ],
  dependencies: [
    polkit_gobject_dep,
    polkit_agent_dep,
  ],
  install: true,
  install_dir: get_option('libexecdir')
)

executable('singularity-polkit-auth-helper',
  sources: helper_sources,
  vala_args: [
    '--pkg=posix',
  ],
  c_args: [
    '-DGETTEXT_PACKAGE="singularity-polkit-agent"',
  ],
  dependencies: [
    gtk4_dep,
    libsingularity_dep,
  ],
  install: true,
  install_dir: get_option('libexecdir')
)
