package com.smartplant.domain.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("control_command_log")
public class ControlCommandLog {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String requestId;
    private String action;
    private String paramsJson;
    private String operator;
    private String topic;
    private String payloadJson;
    private Boolean success;
    private String errorMessage;
    private LocalDateTime createdAt;
}
