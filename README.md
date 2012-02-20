valaninja
=========

A simple project to test how to build a [vala](https://live.gnome.org/Valadoc) app with
[ninja](http://martine.github.com/ninja).

This is a very basic ninja file generation, the idea is not to build an
all purpose ninja configuration builder, it is just a sample of what can
be done to use ninja for vala apps.

You need ruby to rebuild the vala.build configuration file:

```sh
  build/configure > build/vala.ninja
```

but an already generated build/vala.ninja is included for convenience.

To generate the vala build file, you need to run:

```sh
ninja
```

To actually build the vala project, you need to:

```sh
ninja -f build/vala.ninja
```
Or in a single line:

```sh
alias build='ninja > dev/null; ninja -f build/vala.ninja'
build
```

The output should be located on a separate directory, \_obj/.

For your own projects you can tweak the build/configure file to suit
your needs, but bear in mind that the builder is far for complete,
you'll probably need to tweak build/ninja.rb too.
