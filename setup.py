from setuptools import setup, find_packages
setup(
    name="DTConf",
    version="2.0",
    description="Device Tree configuration tool",
    author="Valter Minute",
    author_email="valter.minute@toradex.com",
    packages=['dtconf'],
    package_dir={'mypkg': 'dtconf'},
    package_data={'tdxtests': []},
    scripts=["dtconf"],
)
