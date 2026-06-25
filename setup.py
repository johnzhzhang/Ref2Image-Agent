from setuptools import setup, find_packages

setup(
    name="image_gen_agent",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["google-adk>=2.0", "google-auth", "requests"],
)
