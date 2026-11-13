const lp=require("luaparse");const fs=require("fs");let bad=0;
for(const f of process.argv.slice(2)){try{lp.parse(fs.readFileSync(f,"utf8"),{luaVersion:"5.1"});console.log("OK   "+f.split("/").pop())}catch(e){bad=1;console.log("FAIL "+f+": "+e.message)}}
process.exit(bad)
