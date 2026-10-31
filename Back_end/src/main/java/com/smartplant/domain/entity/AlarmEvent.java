package com.smartplant.domain.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("alarm_event")
public class AlarmEvent {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String alarmType;
    private String message;
    private Boolean active;
    private Long snapshotId;
    private LocalDateTime triggeredAt;
    private LocalDateTime recoveredAt;
}
