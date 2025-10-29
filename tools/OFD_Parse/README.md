# OFD 文件提取

提取 OFD 文件内容，并以 json 格式返回。

## 参数说明

### 启动参数    

启动参数需要根据环境自行输入。

| 参数名称 | 参数类型   | 参数说明 | 默认值 |
| -------- |--------| -------- | ------ |
| `base_url` | string | MaxKB 地址 | `https://<MaxKB_URL>/PORT` |
| `api_key`   | string    | API-KEY，请参见MaxKB右上角头像中API KEY | 'user-xxxxxxxxxxxx'|


### 输入参数    
| 参数名称 | 参数类型 | 参数说明                               | 默认值 |
| -------- |------|------------------------------------| ------ |
| `file_info` | dict | MaxKB 工作流应用中开其他文件（{{开始.other}}）的元素 | |

## 返回说明
返回 json,样式如下： 
{
    "file_name": "xxxx.ofd",
    "document_custom_datas": [
        {
          "Name": "xxxx",
          "Content": "xxx"
        },
    ]
    "pages": [
        {
            "page_id": "Page_0",
            "text_content": "text_content"	
        }	
    ]
}

