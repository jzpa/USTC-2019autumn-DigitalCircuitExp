# USTC 2019autumn DigitalCircic

中国科学技术大学 2019秋 数字电路实验

极限爆肝下的产物，没经过多少测试，可能会有很多 bug 。

* `document/` ：实验报告源码，使用 Latex 排版，使用模板 Elegant Paper，感谢 Elegant Latex 制作组的付出。图片引用为相对路径。
* `rtl/` ：verilog 源码和 coe 文件，同时 `rtl/ip[xx][xxx]` 表示 ip 核，第一个中括号内为名字，第二个中括号为对应的 ip 核生成器
* `tools/` ：包含方便的工具，2019秋的数字电路实验原本提供了一个 word 版本的实验报告模板，而 `Latex调好的封面代码.txt` 可以加在 Latex 文件中，配上科大 logo 可以做到类似的效果