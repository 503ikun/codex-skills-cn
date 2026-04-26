# WPS文档整理分类规则

Use the user's category list as the source of truth. The script classifies by matching normalized file names against category keywords.

Priority:

1. Match explicit keywords from the categories JSON, in the order provided.
2. If a category has no keywords, infer broad keywords from its name.
3. If no category matches, use `--uncertain-category`.

Suggested keyword seeds when the user gives only directory names:

- 采购/订单/合同/报价: `采购`, `订单`, `合同`, `报价`, `付款`, `报销`, `物资`, `原材料`
- 招投标/评审/成交: `招标`, `投标`, `评审`, `评标`, `成交`, `公示`, `公告`, `响应文件`
- 工程/设备/改造: `工程`, `设备`, `改造`, `生产线`, `验收`, `进度`, `计划`
- 财务/付款/报销: `付款`, `报销`, `发票`, `开票`, `保证金`, `费用`
- 人事/个人: `员工`, `试用期`, `考核`, `学历`, `身份证`, `简历`, `人事`
- 学习/论文/资料: `论文`, `学习`, `课程`, `教材`, `文献`, `研究`, `书籍`
- 流程/模板/制度: `模板`, `流程`, `制度`, `办法`, `审批`, `台账`, `用印`, `出差`

Do not force a category when the filename is ambiguous. Put it in the uncertain category and let the user review the CSV.
