import re
import json
import requests
from io import BytesIO
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_PARAGRAPH_ALIGNMENT
from docx.oxml.ns import qn
from docx.enum.style import WD_STYLE_TYPE
from urllib.parse import urljoin


def get_access_token(server_url, username, password):
    login_url = f"{server_url}/?user/index/loginSubmit&name={username}&password={password}"
    try:
        response = requests.get(login_url)
        response.raise_for_status()
        data = response.json()
        if data.get("code") is True:
            access_token = data.get("info")
            print(f"成功获取access_token: {access_token}")
            return access_token
        else:
            print(f"登录失败，响应数据: {data}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"请求登录接口发生异常: {e}")
        return None
    except ValueError:
        print("响应内容不是有效的JSON格式")
        return None


def get_share_info(server_url, access_token, path):
    url = f"{server_url}/index.php?explorer/userShare/get"
    params = {"accessToken": access_token, "path": path}
    try:
        response = requests.post(url, data=params)
        response.raise_for_status()
        result = response.json()
        return {
            "success": result.get("code") is True,
            "data": result.get("data")
        }
    except Exception as e:
        print(f"获取分享信息失败: {e}")
        return {"success": False, "error": str(e)}


def add_share(server_url, access_token, path):
    url = f"{server_url}/index.php?explorer/userShare/add"
    params = {"accessToken": access_token, "path": path}
    try:
        response = requests.post(url, data=params)
        response.raise_for_status()
        result = response.json()
        return {
            "success": result.get("code") is True,
            "data": result.get("data")
        }
    except Exception as e:
        print(f"添加分享失败: {e}")
        return {"success": False, "error": str(e)}


def edit_share(server_url, access_token, share_id, is_link=1, options=None, time_to=0):
    url = f"{server_url}/index.php?explorer/userShare/edit"

    params = {
        "accessToken": access_token,
        "shareID": share_id,
        "isLink": is_link,
        "isShareTo": 0 if is_link == 1 else 1,
        "timeTo": time_to,
        "password": ""
    }

    if options and isinstance(options, dict):
        params["options"] = json.dumps(options)

    try:
        response = requests.post(url, data=params)
        response.raise_for_status()
        result = response.json()

        if result.get("code") is True:
            print(f"分享编辑成功，shareID: {share_id}")
            return {
                "success": True,
                "share_info": result.get("data")
            }
        else:
            print(f"分享编辑失败: {result}")
            return {"success": False, "error": result}

    except Exception as e:
        print(f"编辑分享时发生错误: {str(e)}")
        return {"success": False, "error": str(e)}


def complete_share_process(server_url, access_token, file_path):
    share_info = get_share_info(server_url, access_token, file_path)

    if not share_info.get("success"):
        return share_info

    data = share_info.get("data")

    if not data:
        add_result = add_share(server_url, access_token, file_path)
        if not add_result.get("success"):
            return add_result
        share_id = add_result.get("data", {}).get("shareID")
    else:
        share_id = data.get("shareID")

    share_options = {
        "onlyLogin": "0",
        "notDownload": 0,
        "downloadNumber": "100"
    }

    edit_result = edit_share(
        server_url=server_url,
        access_token=access_token,
        share_id=share_id,
        is_link=1,
        options=share_options,
        time_to=0
    )

    return edit_result


def download_image(image_url):
    """下载图片到内存(BytesIO)，不写入本地文件"""
    try:
        response = requests.get(image_url, stream=True, timeout=15)  # 15秒超时
        response.raise_for_status()  # 捕获HTTP错误

        content_type = response.headers.get("Content-Type", "")
        if not content_type.startswith(("image/jpeg", "image/png", "image/gif")):
            print(f"非图片类型，跳过下载: {content_type}")
            return None

        # 将图片内容存入BytesIO
        image_stream = BytesIO()
        for chunk in response.iter_content(chunk_size=8192):
            if chunk:
                image_stream.write(chunk)


        image_stream.seek(0, 2)
        file_size = image_stream.tell()
        if file_size < 100:
            print(f"图片文件过小（{file_size}字节），视为无效")
            return None

        image_stream.seek(0)  # 重置文件指针到开头
        print(f"图片下载成功（内存中）: {image_url}")
        return image_stream
    except requests.exceptions.RequestException as e:
        print(f"图片下载失败（网络问题）: {str(e)}")
        return None
    except Exception as e:
        print(f"图片处理失败: {str(e)}")
        return None


def set_chinese_font(run):
    """强制设置中文字体为宋体"""
    run.font.name = '宋体'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')


def generate_and_upload_docx(content, server_url, username, password, file_name, base_image_url,
                             upload_dir='{source:7}/'):
    access_token = get_access_token(server_url, username, password)
    if not access_token:
        return "获取access_token失败，无法进行后续操作"

    # 使用BytesIO存储docx内容，不写入本地文件
    docx_stream = BytesIO()

    try:
        doc = Document()

        # 设置文档默认字体为宋体
        style = doc.styles['Normal']
        font = style.font
        font.name = '宋体'
        font.size = Pt(12)
        style._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')

        # 尝试创建自定义样式
        try:
            chinese_style = doc.styles.add_style('ChineseStyle', WD_STYLE_TYPE.PARAGRAPH)
            chinese_style.font.name = '宋体'
            chinese_style.font.size = Pt(12)
            chinese_style._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
        except Exception:
            pass

        lines = content.split('\n')
        current_style = None

        image_pattern = r'!\[(.*?)\]\((.*?)\)'

        for line in lines:
            line = line.strip()
            if not line:
                continue

            try:
                image_match = re.search(image_pattern, line)
            except Exception as e:
                print(f"图片正则匹配失败: {str(e)}")
                image_match = None

            if image_match:
                try:
                    image_desc = image_match.group(1)
                    relative_path = image_match.group(2)

                    print(f"原始图片路径: {relative_path}")

                    if relative_path.startswith('./'):
                        clean_path = relative_path[2:]
                        if base_image_url.endswith('/'):
                            base_image_url = base_image_url.rstrip('/')
                        if clean_path.startswith('/'):
                            clean_path = clean_path[1:]
                        absolute_url = f"{base_image_url}/{clean_path}"
                        print(f"处理相对路径: {relative_path} -> {absolute_url}")

                    elif relative_path.startswith(('http://', 'https://')):
                        if '/admin' not in relative_path:
                            parsed_url = urljoin(relative_path, '/').rstrip('/')
                            path_part = relative_path[len(parsed_url):] if len(relative_path) > len(parsed_url) else ''
                            if path_part.startswith('/'):
                                path_part = path_part[1:]
                            absolute_url = f"{parsed_url}/admin/{path_part}"
                            print(f"修正URL，添加admin路径: {absolute_url}")
                        else:
                            absolute_url = relative_path

                    elif relative_path.startswith('//'):
                        absolute_url = f"https:{relative_path}"
                        if '/admin' not in absolute_url:
                            parsed_url = urljoin(absolute_url, '/').rstrip('/')
                            path_part = absolute_url[len(parsed_url):] if len(absolute_url) > len(parsed_url) else ''
                            if path_part.startswith('/'):
                                path_part = path_part[1:]
                            absolute_url = f"{parsed_url}/admin/{path_part}"

                    elif relative_path.startswith('oss/'):
                        if base_image_url.endswith('/'):
                            base_image_url = base_image_url.rstrip('/')
                        absolute_url = f"{base_image_url}/{relative_path}"
                        print(f"处理oss相对路径: {relative_path} -> {absolute_url}")

                    else:
                        if not relative_path.startswith('/'):
                            relative_path = '/' + relative_path
                        if base_image_url.endswith('/'):
                            base_image_url = base_image_url.rstrip('/')
                        absolute_url = base_image_url + relative_path
                        print(f"处理其他相对路径: {relative_path} -> {absolute_url}")

                    print(f"最终图片绝对路径: {absolute_url}")

                    # 下载图片到内存
                    image_stream = download_image(absolute_url)

                    if image_stream:
                        para = doc.add_paragraph()
                        run = para.add_run()
                        run.add_picture(image_stream, width=Inches(5.5))
                        para.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER

                        if image_desc:
                            caption_para = doc.add_paragraph()
                            caption_run = caption_para.add_run(image_desc)
                            set_chinese_font(caption_run)
                            caption_para.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
                            caption_run.font.size = Pt(10)
                            caption_run.font.italic = True
                    else:
                        para = doc.add_paragraph()
                        error_run = para.add_run(f"[图片加载失败: {absolute_url}]")
                        set_chinese_font(error_run)
                        para.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
                        error_run.font.color.rgb = RGBColor(255, 0, 0)

                    current_style = "image"
                    continue
                except Exception as e:
                    print(f"单张图片处理出错: {str(e)}")
                    para = doc.add_paragraph()
                    exception_run = para.add_run(f"[图片处理异常: {str(e)}]")
                    set_chinese_font(exception_run)
                    para.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
                    continue

            elif line.startswith('# '):
                title_text = line[2:]
                para = doc.add_paragraph()
                run = para.add_run(title_text)
                set_chinese_font(run)
                run.font.size = Pt(24)
                run.font.bold = True
                para.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
                current_style = "title"
            elif line.startswith('## '):
                title_text = line[3:]
                para = doc.add_paragraph()
                run = para.add_run(title_text)
                set_chinese_font(run)
                run.font.size = Pt(18)
                run.font.bold = True
                para.alignment = WD_PARAGRAPH_ALIGNMENT.LEFT
                current_style = "section"
            elif line.startswith('### '):
                title_text = line[4:]
                para = doc.add_paragraph()
                run = para.add_run(title_text)
                set_chinese_font(run)
                run.font.size = Pt(16)
                run.font.bold = True
                para.alignment = WD_PARAGRAPH_ALIGNMENT.LEFT
                current_style = "sub_section"
            elif line.startswith('#### '):
                title_text = line[5:]
                para = doc.add_paragraph()
                run = para.add_run(title_text)
                set_chinese_font(run)
                run.font.size = Pt(14)
                run.font.bold = True
                para.alignment = WD_PARAGRAPH_ALIGNMENT.LEFT
                current_style = "sub_sub_section"
            else:
                para = doc.add_paragraph()
                run = para.add_run(line)
                set_chinese_font(run)
                run.font.size = Pt(12)
                para.alignment = WD_PARAGRAPH_ALIGNMENT.JUSTIFY
                para.paragraph_format.first_line_indent = Pt(20)
                para.paragraph_format.space_before = Pt(6)
                para.paragraph_format.space_after = Pt(6)
                current_style = "paragraph"

        # 保存文档到BytesIO
        doc.save(docx_stream)
        docx_stream.seek(0)  # 重置指针到开头
        print("Word文档已在内存中生成")

    except Exception as e:
        error_msg = f"生成Word文档时出错: {str(e)}"
        print(error_msg)
        return error_msg

    # 上传URL
    upload_url = f"{server_url}/index.php?explorer/upload/fileUpload&accessToken={access_token}"

    # 准备上传文件数据（使用内存流）
    upload_file_name = f"{file_name}.docx"
    files = {
        'file': (upload_file_name, docx_stream)
    }

    data = {
        'path': upload_dir,
        'name': upload_file_name
    }

    try:
        response = requests.post(upload_url, files=files, data=data)

        if response.status_code == 200:
            try:
                result = response.json()
                if result.get('code') is True:
                    print(f"文件 {upload_file_name} 上传成功")
                    uploaded_path = result.get('info')
                    print(f"上传后的文件地址: {uploaded_path}")

                    share_result = complete_share_process(server_url, access_token, uploaded_path)
                    if share_result.get("success"):
                        share_info = share_result.get("share_info")
                        share_hash = share_info.get("shareHash")
                        share_url = f"{server_url}/#s/{share_hash}"
                        print(f"文件分享成功: {share_url}")
                    else:
                        share_url = "创建分享失败"
                        print(f"文件上传成功，但分享处理失败: {share_result.get('error')}")

                    return f"预览与下载链接: {share_url}"
                else:
                    print(f"上传失败: {result}")
                    return f"上传失败: {result}"
            except ValueError:
                error_msg = "错误: 服务器返回非JSON格式响应"
                print(error_msg)
                print("响应内容:", response.text)
                return error_msg
        else:
            error_msg = f"HTTP错误: 状态码 {response.status_code}"
            print(error_msg)
            print(f"响应内容: {response.text}")
            return error_msg

    except Exception as e:
        error_msg = f"上传过程中发生错误: {str(e)}"
        print(error_msg)
        return error_msg
    finally:
        docx_stream.close()