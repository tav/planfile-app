**License**

All work in this repository has been released into the Public Domain.
You are welcome to use it however you wish.

**Installation**

Dependencies:

Assetgen: To build the assets, you need to have [Assetgen](https://github.com/tav/assetgen) installed

Ampify Go packages: To run Planfile, you need to have the [Ampify](http://github.com/tav/ampify) [Go
packages](https://github.com/tav/ampify/tree/master/src/amp) installed.

A sample config file is included as example.config.yaml. 

Subsequently, you need to run the following sequence:

Independently start up Assetgen:    

    $ assetgen --watch --profile=dev
   
Run Planfile:
    
    $ go run planfile.go markdown.go config.yaml -d

Visit http://localhost:8888 in your browser.

--  
Thanks, tav <<tav@espians.com>>
